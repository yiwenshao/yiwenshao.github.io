---
title: linux网络编程系列-地址结构(1)
date: 2016-12-18 18:28:59
tags: [网络编程]
categories: helloworld
---

linux socket编程中经常用到各种类型的地址, 最近在一些开源代码中经常见到,  它们是进行socket编程的基础, 本文对常见的地址结构进行简单整理, 并在附录中对某些函数给出了helloworld式的测试代码, 方便查询.

<!--more-->
### IPV4地址结构

#### in_addr
这个结构内部以网络字节序的32位无符号整数表示的ipv4地址, 在后续介绍的地址结构中会用到这个结构. 之所以一个整数也要放在一个结构体中来代表地址, 是历史原因. 一开始这个结构内部不仅仅是一个整数, 后来演化成只有一个整数, 但是这个结构体保留了. 所以要引用一个IPV4地址, 可以传该结构体, 也可以传结构体中的整数, 这需要根据具体接口的要求正确使用.

```c
struct in_addr { 
in_addr_t s_addr; /* 32-bit IPv4 address */ 
                 /* network byte ordered */ 
};
```

#### sockaddr_in

这个是一个常见的IPV4地址结构, 注释中给出了各个字段的含义与大小. 其中sin_family, sin_port, 以及sin_addr是POSIX规范要求的三个字段, 其他的为额外添加字段. 在POSIX类型中, in_addr_t必须至少是一个32位无符号整数, in_port_t至少是一个16位无符号整数类型, sa_family_t则可以是任意无符合整数类型. 


可以看到, POSIX定义了规范定义了各个结构必须有的字段, 以及字段的大小. 
```c
struct sockaddr_in {
 uint8_t sin_len; /* length of structure (16) */
 sa_family_t sin_family; /* AF_INET */
 in_port_t sin_port; /* 16-bit TCP or UDP port number */
 /* network byte ordered */
 struct in_addr sin_addr; /* 32-bit IPv4 address */
 /* network byte ordered */
 char sin_zero[8]; /* unused */
};
```


#### sockaddr
通用套接字结构, 起来void\*的作用, 在定义这个结构之前, ANSI C还没有出来, 还没有void\*, 这个结构是为了能够处理任意格式的地址参数, 通过指针的方式来传递, 对于socket编程而言, 地址结构作为参数传递的时候一般是通过指针进行的, 而不是直接传递结构体. 结构体在本机内部使用, 而不会在机器直接传递.有了这个结构体, 在接口编写的时候, 要求的参数是struct sockaddr\*类型, 到了函数内部通过类型转换变成具体的地址结构类型.


```c
struct sockaddr {
 uint8_t sa_len;
 sa_family_t sa_family; /* address family: AF_xxx value */
 char sa_data[14]; /* protocol-specific address */
};
```


### IPV6地址结构

#### in6_addr

这个结构使用128bit的空间直接存储一个ipv6的地址. 

```c
struct in6_addr {
 uint8_t s6_addr[16]; /* 128-bit IPv6 address */
 /* network byte ordered */
};

```

#### sockaddr_in6

实际使用的IPV6地址.

```c
#define SIN6_LEN /* required for compile-time tests */
struct sockaddr_in6 {
 uint8_t sin6_len; /* length of this struct (28) */
 sa_family_t sin6_family; /* AF_INET6 */
 in_port_t sin6_port; /* transport layer port# */
 /* network byte ordered */
 uint32_t sin6_flowinfo; /* flow information, undefined */
 struct in6_addr sin6_addr; /* IPv6 address */
 /* network byte ordered */
 uint32_t sin6_scope_id; /* set of interfaces for a scope */
};

```


#### sockaddr_storage

这个结构和sockaddr的区别在于, 足够大, 能够存储任何系统支持的地址结构,且满足任意的对齐要求, 使用的时候, 需要强制类型转化到特定需要的地址结构. 也是通过传指针的方式来使用的. 

```c
struct sockaddr_storage {
 uint8_t ss_len; /* length of this struct (implementation dependent) */
 sa_family_t ss_family; /* address family: AF_xxx value */
 /* implementation-dependent elements to provide:
 * a) alignment sufficient to fulfill the alignment requirements of
 * all socket address types that the system supports.
 * b) enough storage to hold any type of socket address that the
 * system supports.
 */
};

```

#### addrinfo
这个结构可以通过函数getaddrinfo来获取,一方面可以作为getaddrinfo函数调用时候的过滤器, 另一方面可以装getaddrinfo返回的结果(通过参数列表中的指针返回). 可以看到, 其是一个链表结构, 其结构成员如下.
```c
struct addrinfo {
    int ai_flags; // AI_PASSIVE, AI_CANONNAME, etc.
    int ai_family; // AF_INET, AF_INET6, AF_UNSPEC
    int ai_socktype; // SOCK_STREAM, SOCK_DGRAM
    int ai_protocol; // use 0 for "any"
    size_t ai_addrlen; // size of ai_addr in bytes
    struct sockaddr *ai_addr; // struct sockaddr_in or _in6
    char *ai_canonname; // full canonical hostname
    struct addrinfo *ai_next; // linked list, next node
};
```
我们接下来通过getaddrinfo函数来了解这个结构.

首先, 该函数结合了gethostbyname(3) and getservbyname(3)两个函数的功能,也就是说, 该函数支持从名字到地址, 以及从名字到服务端口的转换, 其支持IPV6并且是可重入(reentrant)的.而前两个函数只支持IPV4且不可重入.

这里补充介绍两个过时的函数:
+ gethostbyname 把主机名字映射成Ipv4地址, 返回地址通过hostent结构体来获取, 是一个已经废除的函数, 其函数头如下:
struct hostent *gethostbyname(const char *name);

+ getserverbyname 可以获取服务名字到地址的映射.这个映射通常保存在/etc/services中. 常见的服务如mysql, ftp等.通过名字可以知道这个服务的总体信息

更多关于上面这两个函数的使用, 可以看附录中的测试代码. 

我们开始介绍getaddrinfo函数:

+ getaddrinfo
```
int getaddrinfo(const char *hostname, const char *service,
                       const struct addrinfo *hints,
                       struct addrinfo **res);
```
我们先看参数列表, hostname代表主机名, 也可以传字符串类型的ipv4或者ipv6地址, hints用于对返回什么类型的结果做一个提示(过滤),比如限制只查找IPV4或者只查找IPV6等, 然后res是一个返回结果. 从上面的参数列表, 我们可以看出这个函数的一般使用使用策略:

+ 该函数的参数service运行使用字符串的服务名和字符串类型的端口名, 比如"mysql"或者"3307", 这样我们通过指定参数, 就可以获得对应的addrinfo结构, 这个结构中的struct sockaddr \*ai_addr可以被很多socket相关的接口使用. 该参数可以是NULL.
+ 该函数的hostname参数, 支持字符串结构的地址或者主机名, 比如"www.baidu.com"或者"127.0.0.1", 然后也会返回addrinfo结构. 该参数可以是NULL.
+ 和gethostbyname以及getservbyname类似, getaddrinfo函数也支持对查询操作进行控制(过滤), 这通过传入hints参数来完成, 我们通过hints参数, 可以对需要什么类型的结果做比较细的定制.这个参数也可以是NULL

+ 最后的res用于接收查询的结果. 改函数返回值是0代表执行成功, 否则代表执行失败.

从addrinfo的各个字段的作用来解释这个过滤的机制:

|字段|可能的值|
|-|-|
|int ai_family|AF_INET, AF_INET6, AF_UNSPEC, 分别表示返回的地址限制IPV4,IPV6或者不限制|
|int ai_socktype|SOCK_STREAM, SOCK_DGRAM,0 分别表示返回地址是流模式,数据包模式,以及任意socket类型|
|int ai_protocol|一般使用0, 表示返回地址可以是任意协议|
|int ai_flags|当这个标志是AI_PASSIVE且hostname是NULL的时候, 返回的地址可以用于server端,用于bind和accept, 并且  接受指向本机任意地址的连接.  如果AI_PASSIVE没有被设置, 那么这个返回的地址可以用于client端, 用于connect和sendto等函数, 此时如果hostname是NULL, 则默认是回环地址(127.0.0.1). 如果设置了AI_CANONNAME, 则返回的链表中的第一个节点指向一个名字.|
|socklen_t ai_addrlen|设置为0|
|struct sockaddr *ai_addr|设置为NULL|
|char *ai_canonname|设置为NULL|
|struct addrinfo *ai_next|设置为NULL|

可以看到, addrinfo有两个作用, 其中部分的成员用于过滤返回类型, 还有部分成员用于装返回地址.对于getaddrinfo函数, 其作用是, 分配链表空间, 并在找到所有和提供的service以及hostname匹配项目构造addrinfo, 并且根据hints中的选项做进一步的筛选, 然后通过参数列表中的res返回一个链表头,链表中的每个节点可以看出对之前介绍的地址类型的封装. 函数返回多个addrinfo结构可能有如下原因:

+ 多个网卡
+ 单个网卡支持多种协议AF_INET and AF_INET6
+ 同一个服务有基于 SOCK_DGRAM的, 也有基于 SOCK_STREAM的

需要注意的是, 返回的res结构使用完毕以后, 需要通过freeaddrinfo函数使用资源.

### 补充说明

#### 关于字节序
上面说到网络字节序的问题, 所谓字节序, 就是一个多字节的变量在内存中放置的顺序. 比如一个int占有32个字节, 这个类型的存放方式有两种, 一种是低位存低地址, 叫little endian, 一种是低位存高地址, 叫big endian. 不同的机子对于单字节数据的读取是一致的, 因为它们都以8个bits作为一个byte, 但是对于多字节的数据, 字节序在不同的机子上并没有约定. 对于一个四字节的整数, big endian认为第一个字节位于地址最大的位置, little endian认为第一个字节位于地址最小的位置, 所以网络传输的时候, 需要规定网络字节序,现行的规定是big endian(传输是由低地址到高地址传). 由于不同机器的字节序可能不一样, 所以在进行网络传输的时候, 需要使用ntohxx,htonxx系列的函数进行字节序的转换.在ubuntu下, 可以使用命令**lscpu** 来查看自己的机器是哪种字节序.



### 附录程序

#### gethostbyname

```
#include <stdio.h>
#include <netdb.h>
void printHostent(struct hostent *h){
    //输出canonical 名字
    printf("%s\n",h->h_name);
    switch(h->h_addrtype){
        case AF_INET:{
            //链表的形式给出一系列的IP地址
            char **pptr = h->h_addr_list;
            for(;*pptr!=NULL;pptr++){
                printf("%d.%d.%d.%d\n",(int)pptr[0][0],pptr[0][1],pptr[0][2],pptr[0][3]);
            }
        }
        default:
            break;
    }
}

int main(){
    struct hostent *h;
    //这里参数是主机名
    h=gethostbyname("www.baidu.com");
    printHostent(h);

    h=gethostbyname("localhost");
    printHostent(h);
    return 0;
}
```

#### getservbyname

```
#include <stdio.h>
#include <netdb.h>


//struct servent {
//    char  *s_name;       /* official service name */
//    char **s_aliases;    /* alias list */
//    int    s_port;       /* port number */
//    char  *s_proto;      /* protocol to use */
//}

void printserver(struct servent * s){
    if(s==NULL) return;
    printf("port=%d\n",ntohs(s->s_port));
}

int main(){
    struct servent * s;
    s = getservbyname("domain","udp");
    printserver(s);
    s = getservbyname("ftp","tcp");
    printserver(s);
    s = getservbyname("mysql",NULL);
    printserver(s);

    return 0;
}
```

#### getaddrinfo


下面程序实现了从服务到ip地址的转换, 以及从域名到ip地址的转换.
```
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

#define BUF_SIZE 500

void printInfo(struct addrinfo *result){
    struct addrinfo *rp;
    char buf[BUF_SIZE];
    int i=0;
    for (rp = result; rp != NULL; rp = rp->ai_next) {
       struct sockaddr_in *in = (struct sockaddr_in*)(rp->ai_addr);
       printf("port = %d :",ntohs(in->sin_port));
       inet_ntop(AF_INET, &(in->sin_addr), buf, INET_ADDRSTRLEN);
       printf("ip = %s ",buf);
       printf("name = %s \n",rp->ai_canonname);

    }
}
int main(){
   struct addrinfo hints;
   struct addrinfo *result;
   int sfd, s;
   struct sockaddr_storage peer_addr;
   socklen_t peer_addr_len;
   ssize_t nread;

   //初始化hints, 通过hints来对查找进行提示.
   memset(&hints, 0, sizeof(struct addrinfo));
   //同时运行IPV4和IPV6
   hints.ai_family = AF_UNSPEC;
   hints.ai_socktype = 0;
   hints.ai_flags = AI_PASSIVE|AI_CANONNAME;
   //任意的协议族
   hints.ai_protocol = 0;
   hints.ai_canonname = NULL;
   hints.ai_addr = NULL;
   hints.ai_next = NULL;

   s = getaddrinfo("localhost", "mysql", &hints, &result);
   if (s != 0) {
       fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
       exit(EXIT_FAILURE);
   }
    printInfo(result);

   s = getaddrinfo("localhost", "ftp", &hints, &result);
   if (s != 0) {
       fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
       exit(EXIT_FAILURE);
   }
   printInfo(result);

   s = getaddrinfo("www.baidu.com", NULL, &hints, &result);
   if (s != 0) {
       fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
       exit(EXIT_FAILURE);
   }
   printInfo(result);

   freeaddrinfo(result);
}


```

来自man文档的client/server程序例子:

```
//server端
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>

#define BUF_SIZE 500

int
main(int argc, char *argv[]){
   struct addrinfo hints;
   struct addrinfo *result, *rp;
   int sfd, s;
   struct sockaddr_storage peer_addr;
   socklen_t peer_addr_len;
   ssize_t nread;
   char buf[BUF_SIZE];

   if (argc != 2) {
       fprintf(stderr, "Usage: %s port\n", argv[0]);
       exit(EXIT_FAILURE);
   }

   memset(&hints, 0, sizeof(struct addrinfo));
   hints.ai_family = AF_UNSPEC;    /* Allow IPv4 or IPv6 */
   hints.ai_socktype = SOCK_DGRAM; /* Datagram socket */
   hints.ai_flags = AI_PASSIVE;    /* For wildcard IP address */
   hints.ai_protocol = 0;          /* Any protocol */
   hints.ai_canonname = NULL;
   hints.ai_addr = NULL;
   hints.ai_next = NULL;

   s = getaddrinfo(NULL, argv[1], &hints, &result);
   if (s != 0) {
       fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
       exit(EXIT_FAILURE);
   }

   /* getaddrinfo() returns a list of address structures.
      Try each address until we successfully bind(2).
      If socket(2) (or bind(2)) fails, we (close the socket
      and) try the next address. */

   for (rp = result; rp != NULL; rp = rp->ai_next) {
       sfd = socket(rp->ai_family, rp->ai_socktype,
               rp->ai_protocol);
       if (sfd == -1)
           continue;

       if (bind(sfd, rp->ai_addr, rp->ai_addrlen) == 0)
           break;                  /* Success */

       close(sfd);
   }

   if (rp == NULL) {               /* No address succeeded */
       fprintf(stderr, "Could not bind\n");
       exit(EXIT_FAILURE);
   }

   freeaddrinfo(result);           /* No longer needed */

   /* Read datagrams and echo them back to sender */

   for (;;) {
       peer_addr_len = sizeof(struct sockaddr_storage);
       nread = recvfrom(sfd, buf, BUF_SIZE, 0,
               (struct sockaddr *) &peer_addr, &peer_addr_len);
       if (nread == -1)
           continue;               /* Ignore failed request */

       char host[NI_MAXHOST], service[NI_MAXSERV];

       s = getnameinfo((struct sockaddr *) &peer_addr,
                       peer_addr_len, host, NI_MAXHOST,
                       service, NI_MAXSERV, NI_NUMERICSERV);
      if (s == 0)
           printf("Received %zd bytes from %s:%s\n",
                   nread, host, service);
       else
           fprintf(stderr, "getnameinfo: %s\n", gai_strerror(s));

       if (sendto(sfd, buf, nread, 0,
                   (struct sockaddr *) &peer_addr,
                   peer_addr_len) != nread)
           fprintf(stderr, "Error sending response\n");
   }
}

```


```
//client端
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#define BUF_SIZE 500

int
main(int argc, char *argv[])
{
   struct addrinfo hints;
   struct addrinfo *result, *rp;
   int sfd, s, j;
   size_t len;
   ssize_t nread;
   char buf[BUF_SIZE];

   if (argc < 3) {
       fprintf(stderr, "Usage: %s host port msg...\n", argv[0]);
       exit(EXIT_FAILURE);
   }

   /* Obtain address(es) matching host/port */

   memset(&hints, 0, sizeof(struct addrinfo));
   hints.ai_family = AF_UNSPEC;    /* Allow IPv4 or IPv6 */
   hints.ai_socktype = SOCK_DGRAM; /* Datagram socket */
   hints.ai_flags = 0;
   hints.ai_protocol = 0;          /* Any protocol */

   s = getaddrinfo(argv[1], argv[2], &hints, &result);
   if (s != 0) {
       fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
       exit(EXIT_FAILURE);
   }

   /* getaddrinfo() returns a list of address structures.
      Try each address until we successfully connect(2).
      If socket(2) (or connect(2)) fails, we (close the socket
      and) try the next address. */

   for (rp = result; rp != NULL; rp = rp->ai_next) {
       sfd = socket(rp->ai_family, rp->ai_socktype,
                    rp->ai_protocol);
       if (sfd == -1)
           continue;

       if (connect(sfd, rp->ai_addr, rp->ai_addrlen) != -1)
           break;                  /* Success */

       close(sfd);
   }

   if (rp == NULL) {               /* No address succeeded */
       fprintf(stderr, "Could not connect\n");
       exit(EXIT_FAILURE);
   }

   freeaddrinfo(result);           /* No longer needed */

   /* Send remaining command-line arguments as separate
      datagrams, and read responses from server */

   for (j = 3; j < argc; j++) {
       len = strlen(argv[j]) + 1;
               /* +1 for terminating null byte */

       if (len + 1 > BUF_SIZE) {
           fprintf(stderr,
                   "Ignoring long message in argument %d\n", j);
           continue;
       }

       if (write(sfd, argv[j], len) != len) {
           fprintf(stderr, "partial/failed write\n");
           exit(EXIT_FAILURE);
       }

       nread = read(sfd, buf, BUF_SIZE);
       if (nread == -1) {
           perror("read");
           exit(EXIT_FAILURE);
       }

       printf("Received %zd bytes: %s\n", nread, buf);
   }

   exit(EXIT_SUCCESS);
}

```

参考文献
[[1] http://www.informit.com/articles/article.aspx?p=169505&seqNum=2]()
[[2] Unix network programming, volume 1, 3rd edition, chapter 3,11]()
[[3] man 3 getaddrinfo: http://man7.org/linux/man-pages/man3/getaddrinfo.3.html](http://man7.org/linux/man-pages/man3/getaddrinfo.3.html)
[[4] https://en.wikipedia.org/wiki/Getaddrinfo](https://en.wikipedia.org/wiki/Getaddrinfo)
[[5] https://betterexplained.com/articles/understanding-big-and-little-endian-byte-order/](https://betterexplained.com/articles/understanding-big-and-little-endian-byte-order/)

