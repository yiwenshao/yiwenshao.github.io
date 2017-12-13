---
title: Redis的BIO系统
date: 2016-11-05 16:30:34
tags: [Redis,并发,生产者消费者]
categories: Redis代码解析
---
Redis通过bio系统完成两件事，一是进行Aof持久化，也就是将写入到系统的page cache的数据fsync到磁盘中；二是关闭文件。为了完成这件任务，其采用了任务队列的方式，每个任务都是一个线程来完成，任务会被放到任务队列中，然后由执行任务线程取走，如果队列空，则阻塞等待，如果队列里有任务，就通知工作线程，这通过条件变量来实现。后面以任务初始化，任务放入队列，任务出队列三个方面进行介绍，并且以aof持久化为例说明其在系统中的使用方式，本文基于redis的3.2.3版本代码。
<!--more-->
## 任务初始化

对于一个任务，比如aof持久化任务，首先要初始化一个队列，在redis里面使用了redis自己的链表结构建立这个队列。这个队列需要满足以下特点：

* 生产者放任务到队列中。
* 如果队列不为空，消费者从队列中取任务；否则消费者进入等待状态。

这里的消费者就是服务线程，而为了完成队列为空则等待的功能，redis使用了条件变量机制。其初始化代码如下。

```c
static pthread_t bio_threads[BIO_NUM_OPS];
static pthread_mutex_t bio_mutex[BIO_NUM_OPS];
static pthread_cond_t bio_condvar[BIO_NUM_OPS];
static list *bio_jobs[BIO_NUM_OPS];
```

上面的常量BIO\_NUM\_OPS = 2,表示支持两种任务。对于每种任务，对应一个list用于放置任务，一个pthread\_cond\_t和pthread\_mutex\_t变量用于并发控制，以及一个pthread\_t 用于后台服务线程。
初始化使用了bioInit函数，部分代码如下：

```c
for (j = 0; j < BIO_NUM_OPS; j++) {
    pthread_mutex_init(&bio_mutex[j],NULL);
    pthread_cond_init(&bio_condvar[j],NULL);
    bio_jobs[j] = listCreate();
    bio_pending[j] = 0;
}//初始化锁与条件变量
......
......
for (j = 0; j < BIO_NUM_OPS; j++) { 
    void *arg = (void*)(unsigned long) j;
    //这里的函数参数是arg = j，也就是每个线程传入一个编号j，0代表关闭文件，1代表aof初始化 
    if (pthread_create(&thread,&attr,bioProcessBackgroundJobs,arg) != 0) {    
        serverLog(LL_WARNING,"Fatal: Can't initialize Background Jobs."); 
        exit(1); 
    } 
    bio_threads[j] = thread; 
}//初始化线程
```

在完成初始化任务以后，我们有了BIO\_NUM\_OPS\(其值为2\)个链表表示任务队列，有两个线程调用bioProcessBackgroundJobs函数，参数是一个编号j，并且每个队列都初始化了锁与条件变量做并发控制。

## 任务入队列

任务入队列就是把一个任务放到链表的头部,并且把相应任务的pending值+1,表示这个队列里面未完成的任务多了一个。
其中任务的结构如下：
``` c
struct bio_job {
    time_t time;
    void *arg1, *arg2, *arg3;
};
```
可以看到，任务不是很复杂，只记录一个时间和参数就可以了，后面讲任务执行的时候，会讲到这样一个简单的结构记录的任务怎么执行。任务入队列的代码如下：

```c
void bioCreateBackgroundJob(int type, void *arg1, void *arg2, void *arg3) {
    struct bio_job *job = zmalloc(sizeof(*job));
    job->arg1 = arg1;
 ...
    pthread_mutex_lock(&bio_mutex[type]);
    listAddNodeTail(bio_jobs[type],job);
    bio_pending[type]++;
    pthread_cond_signal(&bio_condvar[type]);
    pthread_mutex_unlock(&bio_mutex[type]);
}
```

这段入队列的代码先为任务结构分配空间，然后使用listAddNodeTail函数把任务放到链表的头部。这里使用的是redis自己实现的链表。可以看到，进行链表操作的时候，要先加锁，这是因为这里的链表是共享资源。在任务成功加入队列以后，调用pthread_cond_signal函数，通知阻塞等待的线程继续执行。上面这个过程是共享变量使用的基本模式:
+ 加锁
+ 置条件为真(这里是任务入队列)
+ 通知
+ 解锁



## 任务出队列
我们已经做好了任务初始化的工作，并且可以在队列里面放置新的任务，那么当队列里面有任务的时候，我们在第一步初始化的时候开启的后台线程就会调用bioProcessBackgroundJobs函数进行任务处理，其处理主要代码如下。

```c
void *bioProcessBackgroundJobs(void *arg) {
    unsigned long type = (unsigned long) arg;
    struct bio_job *job;

    while(1) {
        listNode *ln;

        pthread_mutex_lock(&bio_mutex[type]);        
        if (listLength(bio_jobs[type]) == 0) {
            //条件不成立,等待
            pthread_cond_wait(&bio_condvar[type],&bio_mutex[type]);
            //被通知以后,停止阻塞,重新判断条件
            continue;
        }
        //条件成立,直接执行
        ln = listFirst(bio_jobs[type]);

        job = ln->value;
        //取走值以后,解锁
        pthread_mutex_unlock(&bio_mutex[type]);
        //完成队列处理以后，根据类型调用close函数或者fsync函数。
        if (type == BIO_CLOSE_FILE) {
            close((long)job->arg1);
        } else if (type == BIO_AOF_FSYNC) {
            fsync((long)job->arg1);
        } else {
            serverPanic("Wrong job type in bioProcessBackgroundJobs().");
        }

        pthread_mutex_lock(&bio_mutex[type]);
        listDelNode(bio_jobs[type],ln);
        bio_pending[type]--;
    }
}
```
上面的代码主要流程是，先判断当前的队列是不是空的，如果是空的，则等待。否则，从队列中取出一个job结构，并且根据线程的类型决定调用什么函数。这里的类型通过创建线程是传如的参数获得，可以是0 或者 1。获得类型以后，从job里面取出arg1作为参数，调用close函数或者fsync函数。arg1是一个文件描述符，所以，在任务加入队列的时候，只是需要放一个文件描述符如队列，这也就是为什么bio_job结构体会设置得如此简单。


## Aof持久化的例子
Aof 持久化是redis的两大持久化方式之一，其会以字符串的形式把对redis的每一个操作都先记录在内存的一个buffer中，然后写入文件，并且在适当的时间使用fsync将数据刷入磁盘，而调用fsync的其中一种方式就是使用上面介绍的bio系统，其使用的方式遵循了上面说的三个步骤。

首先，在server.c中的main函数里面，有一个initServer函数，其内部调用了bioInit函数，完成了bio系统的初始化，这样，相关的队列结构被建立，后台线程也被创建了。在redis主循环被启动以后，会进入持久化的时机，调用flushAppendOnlyFile函数，完成aof持久化工作。这个函数会处理aof相关的配置以及优化等各类问题，在本文只关注对bio系统的使用，其相关代码如下：

```c
if (server.aof_fsync == AOF_FSYNC_EVERYSEC)
    sync_in_progress = bioPendingJobsOfType(BIO_AOF_FSYNC) != 0;
......
......
if (!sync_in_progress) aof_background_fsync(server.aof_fd);


```

```c
void aof_background_fsync(int fd) {
    bioCreateBackgroundJob(BIO_AOF_FSYNC,(void*)(long)fd,NULL,NULL);
}

```
可以看到，其通过bioPendingJobsOfType来检查当前队列处理的情况，并且调用bioCreateBackgroundJob来讲aof任务加入队列。由于在前面已经完成了线程的创建，在队列中有任务的时候，线程就会启动，并且通过上面讲的fsync函数完成持久化操作。

## 总结
Redis的Bio是一个非常好的在实际系统中使条件变量的例子.

## 相关文献
[[1] Redis官网](http://redis.io/)
[[2] 条件变量与锁](https://yiwenshao.github.io/2016/11/05/%E6%9D%A1%E4%BB%B6%E5%8F%98%E9%87%8F%E4%B8%8E%E9%94%81/)



