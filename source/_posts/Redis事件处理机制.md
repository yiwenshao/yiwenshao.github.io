---
title: Redis事件处理机制
date: 2017-03-11 16:25:17
tags: [Redis,并发模型,epoll]
categories: Redis代码解析
---

Redis通过IO复用以及单线程模型来处理客户端请求, 其基于epoll,select,kqueue,以及evport封装了自己的事件处理库ae\_event. 这个库的作用是监听多个socket描述符,在描述符上产生读写事件的时候,调用相应的函数进行处理. 具体来说,如果socket可读,则读取数据,进行命令解析,并且将命令回复写到输出缓冲区. 如果socket可写,则将输出缓冲区中的数据通过socket发送给客户端. 此外,还可以借助这个库完成固定时间间隔执行某个函数的功能. 本文首先给出一个实际使用的简单例子,然后基于这个例子介绍相关的API以及其内部的实现原理.

<!--more-->

### 时间事件处理的例子

下面给出一个最简单的基于ae\_event事件库编写的服务端程序,分析其执行过程.程序部分代码如下:

```c
void acceptHandler(aeEventLoop *el,int fd,void *privdata,int mask){
    int cfd;
    struct sockaddr_storage sa;
    socklen_t salen = sizeof(sa);
    cfd = accept(fd,(struct sockaddr*)&sa,&salen);
    if(cfd == -1){
        printf("-1 client\n");
    }else{
        clients[client_index]=cfd;
        client_index++;
    aeCreateFileEvent(el,cfd,AE_READABLE,readHandler,NULL);
    printf("client %d accepted\n",cfd);
    }
}

void writeHandler(aeEventLoop *el,int fd,void*privdata,int mask){
    write(fd,"hello c\n",10);
    aeDeleteFileEvent(el,fd,AE_WRITABLE);
}

void readHandler(aeEventLoop *el,int fd, void *privdata,int mask) {
    char buf[100];
    int n = read(fd,buf,100);
    if(n<=0){
        printf("error read\n");
    } else {
        printf("read=%s\n",buf);
    }
    aeCreateFileEvent(el,fd,AE_WRITABLE,writeHandler,NULL);
}

int main() {
    aeEventLoop *loop=aeCreateEventLoop(64);
    int sfd = create_socket_listen();
    aeCreateFileEvent(loop,sfd,AE_READABLE,acceptHandler,NULL);
    printf("start server\n");
    aeMain(loop);
    return 0;
}
```

这是一个最简单的使用ae\_event事件库处理外部连接事件的示例程序,完整的程序见文末的附件. 该程序启动以后,可以接受外部socket连接, 读取数据,并发送hello返回给客户端. 其中**aeEventLoop**包含了事件处理需要的所有数据, 比如当前要监听的socket队列, 每个socket对应的事件处理函数等.  **aeCreateEventLoop**用于初始化这个结构. 完成初始化以后,可以通过**aeCreateFileEvent**来增加监听的描述符, 然后就可以通过**aeMain**循环等待, 如果监听的描述符上有事件发生,就执行相应的函数.

从上面的程序可以看出, 这个函数库的使用可以分为三步:

* **aeEventLoop \*loop=aeCreateEventLoop\(64\);**
* **aeCreateFileEvent\(loop,sfd,AE\_READABLE,acceptHandler,NULL\);**
* **aeMain\(loop\);**

**第一步**创建了一个事件处理结构, **第二步**为我们server端的socket描述符注册了监听事件, 其中sfd是我们的server端的socket描述符,AE\_READABLE表示监听读事件, acceptHandler表示如果sfd上发生了读事件,就调用acceptHandler函数,最后一个是函数调用时候的参数,在这里不需要.**第三步**表示开始阻塞等待,如果事件发生,就调用我们注册时指定的函数进行事件处理.我们可以多次调用**aeCreateFileEvent**函数来注册更多的事件.

现在, 假设外部有一个client通过connect系统调用连接了我们的server端, 那么根据刚才的设定,acceptHandler函数会被调用, 其内部调用accept函数, 产生一个对应的socket描述符cfd, 然后通过如下的函数调用为这个cfd注册事件:

**aeCreateFileEvent\(el,cfd,AE\_READABLE,readHandler,NULL\);**

其中AE\_READABLE监听这个描述符上的读事件. 而readHandler是一个函数指针,表示如果这个描述符上有读事件,则调用readHander函数.

到这一步,我们已经注册了两个描述符上的事件, 一个是开始的sfd,一个是cfd. 此时,如果刚才的客户端发送一段数据给服务器端,那么根据刚才的设置, readHandler函数会被调用, 其内部通过read函数读取cfd上的数据, 并输出到屏幕, 然后再次通过如下函数调用注册写事件:
**aeCreateFileEvent\(el,fd,AE\_WRITABLE,writeHandler,NULL\);**

经过这步, 当描述符可写的时候, 就会调用writeHandler函数. 通过write系统调用发送"hello"给客户端. 这样就完成了一个非常简单的服务端程序的编写: 接受外部请求并创建相应的socket描述符, 读取client端发送的数据, 向client发送"hello".


### 事件处理机制的实现

#### 事件结构与初始化

本小结分析如何基于基础的epoll系统调用来完成上面所用到的事件处理库.首先看第一步:

**aeEventLoop \*loop=aeCreateEventLoop\(64\);**

其中aeEventLoop部分结构如下

```c
typedef struct aeEventLoop {
    int setsize; /* max number of file descriptors tracked */
    aeFileEvent *events; /* Registered events */
    aeFiredEvent *fired; /* Fired events */
    int stop;
    void *apidata; /* This is used for polling API specific data */
} aeEventLoop;
```

aeFileEvent结构如下:

```c
typedef struct aeFileEvent {
    int mask; /* one of AE_(READABLE|WRITABLE) */
    aeFileProc *rfileProc;
    aeFileProc *wfileProc;
    void *clientData;
} aeFileEvent;

```

aeFiredEvent结构如下:

```c
typedef struct aeFiredEvent {
    int fd;
    int mask;
} aeFiredEvent;
```

**aeCreateEventLoop**函数通过类malloc的函数为一个新的aeEventLoop结构分配空间, 我们关注aeFileEvent\*这个项目. 这个项目是一个指针, 我们传入的64是一个setsize, 内部通过如下的方式让这个指针指向一个数组的头部:

**eventLoop-&gt;events = zmalloc\(sizeof\(aeFileEvent\)\*setsize\);**

可以看到, 在这个例子中, 我们创建了一个大小是64的数组空间.这个空间用于保存所有注册监听的事件. 我们监听的对象是socket描述符, 而描述符可以表示为一个整数, 这样我们要监听k号描述符上的事件,就在events\[k\]上保存这个信息. 根据aeFileEvent的结构可以看出, 这个信息包含了mask,读写函数指针,以及函数调用的时候用到的参数. **举例来说**, 我们想监听5号描述符上的读事件,通过acceptHandler函数进行处理. 那么就把events\[5\]上面的mask设置为AE\_READABLE, rfileProc设置为acceptHandler函数指针. 这样, 如果我们知道5号描述符上发生了读事件, 就通过5下标, 找到其中的函数指针, 然后就可以调用相应的函数处理. 其主要代码如下:

```c
int aeCreateFileEvent(aeEventLoop *eventLoop, int fd, int mask, aeFileProc *proc, 
        void *clientData){
 //取出fd号数组项目 
    aeFileEvent *fe = &eventLoop->events[fd];
//将fd添加如epoll监听
    if (aeApiAddEvent(eventLoop, fd, mask) == -1)
        return AE_ERR;
//mask赋值
    fe->mask |= mask;
//读事件函数指针赋值
    if (mask & AE_READABLE) fe->rfileProc = proc;
//写事件函数指针赋值
    if (mask & AE_WRITABLE) fe->wfileProc = proc;
//参数赋值??
    fe->clientData = clientData;
    if (fd > eventLoop->maxfd)
    return AE_OK;
}
```




#### 事件添加监听

我们注册监听事件的时候,就在我们开辟的数组中添加了一个项目, 并给函数指针赋值来指定处理函数, 然后仅仅是这样,在描述符上发生事件的时候, 是没有办法获得通知的.我们注意到上面的aeCreateFileEvent中有一个函数调用:

**aeApiAddEvent\(eventLoop, fd, mask\)**

这个函数调用底层使用了IO复用机制,起到了事件通知的效果,我们以epoll为例分析如下.


#### 添加描述符监听

我们知道, 要使用epoll对描述符进行监听, 首先要调用epoll_create函数, 然后通过epoll_event 结构获取事件的通知,知道一次等待中有哪些描述符发生了事件, 以及是读事件还是写事件. epoll提供了这个信息以后, 我们就可以通过上面介绍的数组的机制, 找到相应的函数指针并执行. 这就是ae_event事件触发机制的实现过程, 通过epoll知道哪个fd上发生了事件,以及是读事件还是写事件, 然后以fd为下标找到相应的函数来处理这个事件.下面给出epoll的封装方式:


**aeApiCreate**
这个函数封装了IO复用需要的相关数据结构的初始化, 对于epoll来说, 是调用epoll_create时产生的描述符,以及等待时使用的epoll_event结构, 类似的如果使用select, 则是fd_set结构, 其代码如下:

```c
typedef struct aeApiState {
    int epfd;
    struct epoll_event *events;
} aeApiState;

static int aeApiCreate(aeEventLoop *eventLoop) {
    aeApiState *state = zmalloc(sizeof(aeApiState));
    state->events = zmalloc(sizeof(struct epoll_event)*eventLoop->setsize);
    state->epfd = epoll_create(1024); /* 1024 is just a hint for the kernel */
    //apidata是void*, 用于保存IO复用需要用的的数据结构, 对外封装成aeApiState
    eventLoop->apidata = state;
    return 0;
}
```

**aeApiaddEvent**
在完成IO复用的基本数据结构的初始化以后, 就可以为特定的描述符注册监听事件, 对epoll而言可以通过epoll_ctl来完成, aeApiaddEvent是对这个系统调用的封装, 其代码如下:

```c
static int aeApiAddEvent(aeEventLoop *eventLoop, int fd, int mask) {
    aeApiState *state = eventLoop->apidata;
    struct epoll_event ee = {0}; /* avoid valgrind warning */
    /* If the fd was already monitored for some event, we need a MOD
     * operation. Otherwise we need an ADD operation. */
    int op = eventLoop->events[fd].mask == AE_NONE ?
            EPOLL_CTL_ADD : EPOLL_CTL_MOD;
    ee.events = 0;
    mask |= eventLoop->events[fd].mask; /* Merge old events */
    if (mask & AE_READABLE) ee.events |= EPOLLIN;
    if (mask & AE_WRITABLE) ee.events |= EPOLLOUT;
    ee.data.fd = fd;
    if (epoll_ctl(state->epfd,op,fd,&ee) == -1) return -1;
    return 0;
}
```
可以看到, 上面这段代码可以指定fd, 以及mask, 来决定针对某个fd添加读事件或者写事件的监听. 相应的, 我们也可以删除fd上事件的监听. 
```
static void aeApiDelEvent(aeEventLoop *eventLoop, int fd, int delmask) {
 aeApiState *state = eventLoop->apidata;
 struct epoll_event ee = {0}; /* avoid valgrind warning */
 int mask = eventLoop->events[fd].mask & (~delmask);

 ee.events = 0;
 if (mask & AE_READABLE) ee.events |= EPOLLIN;
 if (mask & AE_WRITABLE) ee.events |= EPOLLOUT;
 ee.data.fd = fd;
 if (mask != AE_NONE) {
 epoll_ctl(state->epfd,EPOLL_CTL_MOD,fd,&ee);
 } else {
 /* Note, Kernel < 2.6.9 requires a non null event pointer even for
 * EPOLL_CTL_DEL. */
 epoll_ctl(state->epfd,EPOLL_CTL_DEL,fd,&ee);
 }
}
```
**aeApiPoll**
在完成描述符上的事件监听注册以后, 就可以开始阻塞等待外部事件, 对于epoll而言,就是调用epoll_wait. aeApiPoll完成了对epoll_wait的封装. 

```c
static int aeApiPoll(aeEventLoop *eventLoop, struct timeval *tvp) {
     aeApiState *state = eventLoop->apidata;
     int retval, numevents = 0;

     retval = epoll_wait(state->epfd,state->events,eventLoop->setsize,
     tvp ? (tvp->tv_sec*1000 + tvp->tv_usec/1000) : -1);
     if (retval > 0) {
     int j;

     numevents = retval;
     for (j = 0; j < numevents; j++) {
     int mask = 0;
     struct epoll_event *e = state->events+j;

     if (e->events & EPOLLIN) mask |= AE_READABLE;
     if (e->events & EPOLLOUT) mask |= AE_WRITABLE;
     if (e->events & EPOLLERR) mask |= AE_WRITABLE;
     if (e->events & EPOLLHUP) mask |= AE_WRITABLE;
     eventLoop->fired[j].fd = e->data.fd;
     eventLoop->fired[j].mask = mask;
     }
     }
     return numevents;
}

```
这个函数起到了阻塞等待的作用, 如果外部有事件发生, 则把相关的信息保存在上面讲到的数组中. 并返回numevents. 需要注意的是, 这里借助了firedEvents这个结构.举例来说, 现在有 3 4 5 6 这四个描述符上分别发生了read/read/write/write事件, 这个信息通过epoll机制下的epoll_event获取, 并保存在fired数组的前四项, 返回numevents为4.这样, 我们在后续进行事件处理的时候, 只要遍历这个数组, 就可以找到相应的fd作为下标, 然后通过前面介绍的aeFileEvent \*events 结构, 调用相应的函数进行处理. 至此, 我们完成了事件通知以及事件处理的框架的建立.
![aeFiredEvent数组](http://om7yuntkk.bkt.clouddn.com/aeFiredEvent.png) 



#### aeMain
aeMain是比较上层的接口, 一开始的例子讲解了ae_event函数库使用的三部, 调用aeMain是最后一步. 在前两部, 我们完成了事件的注册, 定义了事件处理函数, 并讲解了其内部事件通知的方式, 这里我们通过这个函数的分析, 解释上面说到的这些封装是怎么使用的. 

```c
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;

    while (!eventLoop->stop) {
        aeProcessEvents(eventLoop, AE_ALL_EVENTS);
 }
}

int aeProcessEvents(aeEventLoop *eventLoop, int flags){
 int processed = 0, numevents;
 //此处省略设置tvp的代码
 numevents = aeApiPoll(eventLoop, tvp);
 for (j = 0; j < numevents; j++) {
 aeFileEvent *fe = &eventLoop->events[eventLoop->fired[j].fd];
 int mask = eventLoop->fired[j].mask;
 int fd = eventLoop->fired[j].fd;
 int rfired = 0;
 if (fe->mask & mask & AE_READABLE) {
 rfired = 1;
 fe->rfileProc(eventLoop,fd,fe->clientData,mask);
 }
 if (fe->mask & mask & AE_WRITABLE) {
 if (!rfired || fe->wfileProc != fe->rfileProc)
 fe->wfileProc(eventLoop,fd,fe->clientData,mask);
 }
 processed++;
 } 

 if (flags & AE_TIME_EVENTS) // 事件事件处理,此处不考虑
 processed += processTimeEvents(eventLoop);

 return processed;
}

```
可以看到, 该函数首先设置tvp,也就是阻塞等待的最长时间, 然后通过之前介绍的aeApiPoll阻塞等待, 如果发生了事件, 其内部将这个信息保存在eventLoop->fired数组中, 并返回numevents, 然后就开始使用for循环对每个发生事件的描述符进行处理. 处理的方式是以描述符为下标, 取出eventLoop->events数组中的项目, 然后调用我们之前注册事件的时候设置好的函数. 至此, 事件处理的基本流程已经完成了. 


### 事件触发机制的总结
通过上面的分析可以知道, redis的事件处理库可以为描述符注册监听事件, 并处理发生在socket描述符上的读写事件. 其底层通过IO复用的机制获得了"哪些描述符上发生了事件"以及"是读事件还是写事件"这两个信息, 然后通过数组来保存这个信息,最后通过遍历数组的方式对各个描述符上的事件一个一个进行处理.

下图展示了其封装的层次.对于这样一个事件处理的流程, 可以抽象为三个步骤, 第一步是相关数据结构的初始化,第二步是为描述符注册事件,或者删除注册的事件, 第三步是阻塞等待事件发生,并且在事件发生以后返回事件信息进行后续处理. 第四步是结束处理,释放相关资源. 常见的IO服用方式select, epoll, kqueue, evport都能完成这4个功能. 所以redis对这四步进行了封装, 统一了其中的接口, 形成了图中第二层以aeApi开头的一系列函数, 每个系统调用需要的数据则是统一封装成一个aeApiState结构体, 对于epoll是epoll_event, 对于select是fd_set, 这样在使用的时候, 不管底层用了那种IO复用机制, 都可以使用统一的接口了. 在这层之上, 给除了编程人员用户的上层接口,封装了事件处理的细节. 我们要通过数组保存事件, 循环处理事件, 这些部分要用到的数据结构, 以及aeApiState都封装成了一个aeEventLoop接口, 使用者只需要在初始化的时候指定一个初始大小, 并且根据需要添加和删除事件, 然后调用aeMain就可以阻塞等待,并自动处理事件, 不需要知道底层的细节. 
![](http://om7yuntkk.bkt.clouddn.com/ae_event_level.png)




### 附录代码及编译

理解一个机制, 除了看代码, 还需要用它来实现一些东西, 这样才能有直观的感受, 本节给出完整的代码如下. 

编译可以借助hiredis现成的makefile文件, 把其中的hiredis-example-ae, export AE_DIR, 然后使用make hiredis-example-ae即可编译运行.


+ 服务器

```
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <hiredis.h>
#include <async.h>
#include <adapters/ae.h>

void readHandler(aeEventLoop *el,int fd, void *privdata,int mask);

//int clients[10000];

int create_socket_listen(){
    int sockfd;
    int len;
    int port = 6666;
    int queueLength = 5;
    sockfd = socket(AF_INET,SOCK_STREAM,0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);    
    len = sizeof(address);
    bind(sockfd,(struct sockaddr*)&address,len);
    listen(sockfd,queueLength);
    printf("this is function \n \
     serverSocket_create_and_listen in net.c \n \
      finish listen and bind in port = %d \n",port); 
    return sockfd;
}

void acceptHandler(aeEventLoop *el,int fd,void *privdata,int mask){
    int cfd;
    struct sockaddr_storage sa;
    socklen_t salen = sizeof(sa);
    cfd = accept(fd,(struct sockaddr*)&sa,&salen);
    if(cfd == -1){
        printf("-1 client\n");
    }else{
//        clients[client_index]=cfd;
//        client_index++;
    aeCreateFileEvent(el,cfd,AE_READABLE,readHandler,NULL);
    printf("client %d accepted\n",cfd);
    }
}

void writeHandler(aeEventLoop *el,int fd,void*privdata,int mask){
    write(fd,"hello c\n",10);
    aeDeleteFileEvent(el,fd,AE_WRITABLE);
}

void readHandler(aeEventLoop *el,int fd, void *privdata,int mask) {
    char buf[100];
    int n = read(fd,buf,100);
    if(n<=0){
        printf("error read\n");
    } else {
        printf("read=%s\n",buf);
    }
    aeCreateFileEvent(el,fd,AE_WRITABLE,writeHandler,NULL);
}

int main() {
    aeEventLoop *loop=aeCreateEventLoop(64);
    int sfd = create_socket_listen();
    aeCreateFileEvent(loop,sfd,AE_READABLE,acceptHandler,NULL);
    printf("start server\n");
    aeMain(loop);
    return 0;
}
```


+ 客户端

```
#!/usr/bin/env python  
import socket;
if "__main__" == __name__:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    sock.connect(('localhost', 6666));
    sock.send('0xxxxx');
    szBuf = sock.recv(1024);
    print("recv " + szBuf);
    sock.close();
    print("end of connect");
```


### 相关文献

[[1]Redis官网](https://redis.io)
[[2]Redis设计与实现 黄健宏]()



