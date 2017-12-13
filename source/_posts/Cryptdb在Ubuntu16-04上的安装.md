---
title: Cryptdb在Ubuntu16.04上的安装
date: 2016-11-12 17:04:40
tags: MySQL
categories: database
---

Cryptdb是MIT的开源数据库加密层, 其实现了数据加密操作, 代码在Ubuntu12.04上进行过测试. 但是12.04对于现在来说太老了, 在Ubuntu16.04系统上直接使用脚本安装会出现各种问题, 网上现有的参考资料也比较少. 本文基于对其安装脚本的分析, 给出了Ubuntu16.04上安装的分解步骤.该方法在Ubuntu16.04上测试通过.

<!--more-->

### 前期准备
Cryptdb的安装主要可以分为安装MySQL与相关软件, 安装MySQL-Proxy, 以及编译安装Cryptdb三个部分.前期需要安装一些依赖的软件, 其具体步骤如下:

* 下载源码

```c
git clone -b public git://g.csail.mit.edu/cryptdb
```

下载以后, 得到一个**cryptdb.tar.gz**文件, 解压可以获得一个Cryptdb文件夹, 进入该文件夹.为了方便说明, 我们定义该文件夹路径是$CRYPTDB\_HOME.

* 下载必要的依赖软件

```c
sudo apt-get install gawk liblua5.1-0-dev libntl-dev \
libmysqlclient-dev libssl-dev libbsd-dev libevent-dev \
libglib2.0-dev libgmp-dev mysql-server libaio-dev \
automake gtk-doc-tools flex cmake libncurses5-dev make\
ruby lua5.1 libmysqld-dev
(文末给出脚本链接, 也可以参考其安装脚本)
```
上面的过程会安装MySQL, 需要设置root用户的密码, 为了方便在这里设置密码为**letmein**.
由于Cryptdb的语法解析依赖bison2.7, 而默认安装的不是2.7版本, 所以需要手动安装bison2.7, 文末的连接给出了手动bison2.7的安装包.

此外, 还需要安装g++4.7版本.
```
sudo apt install g++-4.7
```

* 安装MySQL-Proxy

脚本中采用了直接编译源码的方式来安装MySQL-Proxy, 这样会比较麻烦, 在Ubuntu16.04条件下出现很多的问题, 所以可以直接使用编译好的版本.

1. 在[官网](https://downloads.mysql.com/archives/proxy/)下载mysql-proxy0.8.5.
2. 进入$CRYPTDB\_HOME\/bins\/proxy-bin目录,并解压,可以看到bin,lib,include,libexc,share,licenses文件夹
3. 设置环境变量

通过这样简单的三步操作, 就完成了mysql-proxy的安装.

### 编译MySQL与Cryptdb

+ 配置MySQL

再次进入Cryptdb目录, 使用tar -zxf bins\/mysql-src.tar.gz 命令解压MySQL源码.并且进入mysql-src目录, 进行如下操作.

```c
mkdir build
cd build
export CXX=g++-4.7
cmake -DWITH_EMBEDDED_SERVER=on -DENABLE_DTRACE=off ..
make
```
根据官方文档的说法, 现在的MySQL依赖C++的boost库, 所以如果用的是新版的MySQL, 可以使用如下的命令[下载boost](http://dev.mysql.com/doc/refman/5.7/en/source-installation.html):

```c
cmake -DWITH_EMBEDDED_SERVER=on -DENABLE_DTRACE=off -DDOWNLOAD_BOOST=1 -DWITH_BOOST=~/boostmysql ..
```


* 添加配置文件

在Cryptdb目录下的conf目录中, 创建一个新文件config.mk, 文件内容示例如下:

```c
MYSRC := /home/shaoyiwen/cryptdb/mysql-src
MYBUILD := $(MYSRC)/build
RPATH := 1
CXX := g++-4.7
MYSQL_PLUGIN_DIR := /usr/lib/mysql/plugin
```

其中MYSRC变量的值根据自己的实际配置环境进行修改.

* 编译Cryptdb

```
make clean
make
sudo make install
```

到此, Cryptdb编译就完成了, 最后在.bashrc中田间EDBDIR变量,并设置权限, 就完成了所有的安装工作.

```
export EDBDIR=$CRYPTDB_HOME
chown -R 用户名  $CRYPTDB_HOME
```
* 启动Cryptdb

要启动Cryptdb, 首先需要写一个简单的配置文件mysql-proxy.cnf:

```c
[mysql-proxy]
plugins = proxy
event-threads = 4
proxy-lua-script = /home/shaoyiwen/Desktop/cryptdb/mysqlproxy/wrapper.lua
proxy-address = 192.168.124.138:3307
proxy-backend-addresses = localhost:3306
```

其中wrapper.lua的路径根据自己机器的机器配置修改. 并且赋予mysql-proxy.cnf **0600**权限.

```
chmod 0660 mysql-proxy.cnf
```

然后就可以使用如下命令启动MySQL-Proxy, 并且在MySQL客户端使用3307端口接入数据库了.

```
mysql-proxy --defaults-file=./mysql-proxy
```

### 总结
Cryptdb基于MySQL-Proxy来实现, 通过wrapper.lua脚本, 截获客户端发送的SQL语句请求, 进行数据加解密的处理. 在MySQL-Proxy端, 需要安装Cryptdb的动态链接库来完成这些操作, 在MySQL服务器端, 则是使用了MySQL的UDF功能, 进行加密层次的调整. 了解了这种结构, 就可以手动安装, 并在各个小的步骤出现问题的时候, 采用对应的方法进行解决. 



