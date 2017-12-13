---
title: Redis集群搭建方法
date: 2016-10-05 10:45:01
tags: Redis
category: database
---
本文讲述了Redis集群搭建的基本方法, 然后给出一个使用一键配置的脚本搭建Redis集群的方法,本文编写时Redis处于3.2.4版本.
<!--more-->
### 基本的搭建方法

#### 单机redis启动

单机的redis启动非常方便. 分为以下步骤:

1. 在[Redis官网](http://redis.io/) 下载Redis源码, 并且解压, 获得一个 **redis-3.2.4**文件夹
2. 进入./redis-3.2.4/src 运行make命令编译, 如果编译通过, 运行make test进行检测
3. 完成上述的两步以后, 可以获得一个可执行文件 **redis-server**, 一个redis客户端**redis-cli**,一个集群配置脚本redis-trib.rb 并且在./redis-3.2.4中, 有一个配置文件**redis.conf**, 我们拷贝这四个文件到一个文件夹中, 后续的所有操作只需要基于这四个文件

通过上述的三个步骤, 我们获得了四个文件, 此时只要运行命令 **./redis-server redis.conf**, 就可以启动单机的redis了. 默认的情况下, redis使用IP是127.0.0.1, 端口是6667, 所以可以使用**./redis-cli -p 6667 -h 127.0.0.1** 来连接到redis服务器. 连接成功以后, 就可以通过命令行给redis服务器发送命令, 进行数据库操作.

#### 修改配置文件

为了能够创建redis集群, 需要修改配置文件, 在此对配置文件进行说明.

首先给出默认情况下的部分配置文件:

```
bind 127.0.0.1
protected-mode yes
port 6379
# cluster-enabled yes
```

为了启动集群, 把上述的配置改成

```
#bind 127.0.0.1
protected-mode no
port 6379
cluster-enabled yes
```

这样, 我们的配置文件就开启了集群模式, 此时以**./redis-server redis.conf**启动redis服务, 就是以集群模式启动的.

#### 启动多个redis实例

完成上述的配置以后, 我们就可以启动多个redis进程, 为最终的集群创建做准备. 每个redis实例由**一个IP地址+端口号**来识别. 我们可以在一台机器上启动多个redis进程, 用这些进程构建一个redis集群, 也可以把这些reids进程放在不同的机器上构成redis集群. 在本次的例子中, 我们以单机为例子, 多机的情况和单机的配置几乎没有区别.

下面以单机启动三个redis实例为例子:

1. 创建三个文件夹, 分别是6667 6668 6669, 然后复制我们刚才的到的redis-server以及redis.conf到这三个文件夹中
2. 修改配置文件redis.conf, 使得port 6379 分别变成port 6667 ; port 6668 ; port 6669. 也就是他们的port值和所处的文件夹对应
3. 分别进入三个文件夹, 使用命令**./redis-server redis.conf** 启动redis

至此, 多个redis 已经启动, 接下来需要完成最后一步, 也就是redis 集群的握手.

#### 启动redis集群

要启动redis集群, 仅仅启动多个redis进程是不够的, 它们还需要完成握手, 才可以形成一个可以工作的redis集群. 
这个工作需要通过redis-trib.rb脚本来完成, 上面已经做过介绍. 要使用这个脚本, 需要进行相关环境的配置, 如下:

```c
yum install ruby
yum install rubygems
gem install redis
```

对于其他的linux发行版, 可以使用相应的命令 如apt get 进行安装. 其中上述的第三条命令由于网络原因往往不能执行成功, 可以根据文末[2]给出的链接下载redis-3.2.1.gem文件, 然后使用

**gem install -l ./redis-3.2.1.gem** 命令

进行安装. 
完成上面的安装步骤以后, 就可以运行如下的命令完成集群的搭建工作:

```
./redis-trib.rb create --replicas 0 127.0.0.1:6667 127.0.0.1:6668  127.0.0.1:6669
```

可以看到, --replicas 0 后面对应的三个ip:port对正好就是我们刚才启动的三个redis实例. 如果我们在多台机器上启动redis, 只需要把对应的ip和port进行修改就可以了. 这个命令运行以后, 如果正常执行, 会要求用户输入yes, 输入yes并且回车, 就可以看到集群创建成功的提示了. 其中--replicas 0表示0个slave, 可以根据需要设置成其他值.

#### 测试redis集群

redis集群的连接, 可以通过集群中任意一个redis进程的ip和端口来完成. 比如根据上面的配置, 我们可以通过127.0.0.1:6667 来接入集群. 我们运行如下命令:

**./redis-cli -c -p 6667 -h 127.0.0.1**

就可以接入redis集群了. 然后输入 **set k v** 可以看到OK的回复, 继续输入**get k**可以看到v作为返回值. 通过这样简单的交互, 我们的redis集群就搭建完成了.


### 使用脚本搭建redis集群

#### 脚本的使用
首先, 需要在[启动脚本](https://github.com/yiwenshao/Create_Redis_Cluster)下载脚本.
然后进行下面的配置:

+ 在hosts文件中配置自己的目标IP地址和端口号, 示例如下:
```
192.168.1.22 6667
192.168.1.23 6668
192.168.1.24 6669
192.168.1.25 6670
```
上面的这种配置指定了四台机器, 以及每台机器上运行的redis的端口号.

+ 配置机器登录的用户名

在create.sh的第二行, USER=guest, 修改成机器的登录帐号. 比如使用root用户登录, 则改为USER=root. 因为脚本需要使用ssh登录到上面指定的机器中启动redis, 所以最好在配置好用户名以后, 设置ssh面密码登录. 这样启动的时候会比较方便.

+ 启动redis集群

完成上面的配置以后, 就可以使用命令启动集群了:**./create.sh -n 1**. 这个命令会登录上面指定的4台机器, 并启动redis, 然后使用redis-trib.rb启动redis集群.

+ 单机多实例

redis是单线程处理的, 为了发挥多核处理器的作用, 常常在单台机器上启动多个reids实例, 在上面的配置下, 可以使用如下命令在每台机器上启动两个或多个redis实例:

**./create.sh -n 2**

以此类推, 如果要每台启动k个实例, 就把上面的2替换成相应的k.我们在上面配置了四台机器, 那么每台机器启动两个实例, 总体就是8个redis实例.


### 脚本的更多配置

#### redis.conf以及redis版本
我们可以看到,下载的脚本中有一个data目录, 内部有redis.conf配置文件. 需要保证如下的配置:
```
#bind 127.0.0.1
protected-mode no
cluster-enabled yes
daemonize yes
```
其他的配置可以根据自己的需要来完成. 在data中已经有编译好的redis-server, 可以用自己编译的redis-server文件进行替换. 配置文件redis.conf也可以替换成自己的配置文件, 只要保证上面列出的四个配置就可以了.这样, 我们可以根据需要使用不同版本的redis-server以及对应的配置文件.

### 相关文献参考

\[1\] [Redis官网](http://redis.io/topics/cluster-tutorial)

\[2\] [集群创建脚本](https://github.com/yiwenshao/Create_Redis_Cluster)
