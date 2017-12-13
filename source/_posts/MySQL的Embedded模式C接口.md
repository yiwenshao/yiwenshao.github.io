---
title: MySQL的Embedded模式C接口
date: 2017-01-01 17:32:26
tags: Cryptdb
categories: MySQL
---

MySQL除了CS运行模式, 还有embedded模式. 相关文档介绍比较少,也比较散乱, 最近项目中正好用到, 现通过本文对其基本用法做个介绍,给出可以运行的基本例子.本文基于mysql5.5.

<!--more-->

#### 环境配置
要使用embedded模式的MySQL, 有两种方法, 一种是从源码编译, 一种是下载libmysqld库. 本文首先采用下载库的方法, 在ubuntu16.04上, 有如下的命令.

```
sudo apt install libmysqld-dev
```

下载完成以后, 在相应的接口代码中, 使用如下的选项进行编译和链接即可. 

```
`mysql_config --include --libmysqld-libs`
```

libmysqld中开放的接口有限, 如果选择从源码编译, 除了可以用基本的embedded的功能外, 还能用到其他有意思的功能, 比如调用MySQL解析器, 这个将在后续的文章中介绍. 



#### 运行基本程序
为了验证是否安装成功, 写一个如下的小程序, 并且编译运行. 在运行前, 先在当前目录创建一个新的文件夹**shadow**

```
//代码下载:https://github.com/yiwenshao/code_for_blog/blob/master/2017/1/MySQL的Embedded模式C接口/Embed.cc
#include<stdio.h>
#include<mysql.h>
#include<my_global.h>
static bool lib_initialized = false;

int main(){
    if (!__sync_bool_compare_and_swap(&lib_initialized, false, true)) {
        return 0;
    }
    char dir_arg[1024];
    snprintf(dir_arg, sizeof(dir_arg), "--datadir=%s", "./shadow");
    char *mysql_av[5]=
    { "progname",
            "--skip-grant-tables",
            dir_arg,
            "--character-set-server=utf8",
            "--language=/home/casualet/Desktop/cryptdb/mysql-src/build/sql/share/"
    };

    assert(0 == mysql_library_init(sizeof(mysql_av)/sizeof(mysql_av[0]),(char**) mysql_av, 0));
    assert(0 == mysql_thread_init());
    MYSQL* mysql = mysql_init(NULL);
    if(mysql==NULL){
        printf("error 26\n");
    }else{
        printf("mysql init succeed\n");
    }
    mysql_options(mysql, MYSQL_READ_DEFAULT_GROUP, "libmysqld_client");
    mysql_options(mysql, MYSQL_OPT_USE_EMBEDDED_CONNECTION, NULL);
    mysql_real_connect(mysql, NULL, NULL, NULL, "information_schema", 0, NULL, 0);

    mysql_query(mysql, "SHOW DATABASES;");
    MYSQL_RES *results = mysql_store_result(mysql);
    MYSQL_ROW record;

    while(record=mysql_fetch_row(results)){
        printf("hehe\n");
        printf("%s\n", record[0]);
    }

    mysql_query(mysql, "CREATE DATABASE testdb1;");

    return 0;
}
```
上面的代码通过如下的命令编译:

```
g++ -o Embed Embed.cc `mysql_config --include --libmysqld-libs` -std=c++11
```

作为对比, 如果使用的是cs模式的接口, 使用如下的编译方法

```c
sudo apt-get install libmysqlclient-dev
`mysql_config --cflags --libs`
```
如果该程序成功运行且没有错误, 则基本配置成功. 下面对具体的接口进行介绍.


#### 完整的接口介绍和多线程环境

给出一段如下所示的实例程序:

```
//代码下载:https://github.com/yiwenshao/code_for_blog/blob/master/2017/1/MySQL的Embedded模式C接口/full.cc
#include<iostream>
#include<stdio.h>
#include<string>
#include<memory>
#include<vector>
#include<tuple>
#include <pthread.h>
#include<mysql.h>
#include<my_global.h>
#define THREAD_NUM 16
using namespace std;
static bool lib_initialized = false;
//调用出错是用到的函数
void finish_with_error(MYSQL *con){
    fprintf(stderr, "%s\n", mysql_error(con));
    mysql_close(con);
    return;
}
//获得命令执行的结果.
void mysql_result_wrapper(MYSQL *con){
    MYSQL_RES *result = mysql_store_result(con);
    if(result == NULL) return;
    int num_fields = mysql_num_fields(result);
    if(num_fields==0) return;
    MYSQL_FIELD *field;
    MYSQL_ROW row;
    //获得参数affected rows.
    printf("%ld products updated",
       (long) mysql_affected_rows(con));

    while(row = mysql_fetch_row(result)){
        for(int i = 0; i < num_fields; i++) {
          if (i == 0)
          {
             while(field = mysql_fetch_field(result))
             {
                 printf("%s ", field->name);
                 printf("%d ",field->type);
             }
             printf("\n");
          }
            printf("%s ", row[i] ? row[i] : "NULL");
        }
        //以数组的方式返回get的当前row的所有字段的长度
        //const unsigned long *const l = mysql_fetch_lengths(result);
        //for(int i = 0; i < num_fields; i++) {
        //    cout<<l[i]<<"\t"<<endl;
        //}
    }
    printf("\n");
}
//发送单个MySQL命令
void mysql_query_wrapper(MYSQL *con,string s){
    if(mysql_query(con, s.c_str())) {
        finish_with_error(con);
    }
    mysql_result_wrapper(con);
}
//初始化MySQL
void init_mysql(){
    //保证该函数只被调用一次
    if (!__sync_bool_compare_and_swap(&lib_initialized, false, true)) {
        return ;
    }
    char dir_arg[1024];
    snprintf(dir_arg, sizeof(dir_arg), "--datadir=%s", "./shadow");
    //第一个参数被忽略, 一般给个名字. 所有参数会复制, 所以调用以后销毁参数是可以的.用这个函数, 是为了多线程,否则mysql_init就可以了.
    char *mysql_av[4]=
    { "progname",
            "--skip-grant-tables",
            dir_arg,
            "--character-set-server=utf8"
    };
    //int mysql_library_init(int argc, char **argv, char **groups)
    assert(0 == mysql_library_init(sizeof(mysql_av)/sizeof(mysql_av[0]),(char**) mysql_av, 0));
    //多线程条件下, 每个线程在使用mysql库中的函数时, 都要调用该函数进行初始化.
    assert(0 == mysql_thread_init());
}
void *thread_func(void *arg) {
    int v = (long)arg;
    //每个线程使用mysql相关的函数之前, 先调用该函数进行初始化.
    assert(0 == mysql_thread_init());
    MYSQL* mysql = mysql_init(NULL);
    mysql_options(mysql, MYSQL_READ_DEFAULT_GROUP, "libmysqld_client");
    mysql_options(mysql, MYSQL_OPT_USE_EMBEDDED_CONNECTION, NULL);
    mysql_real_connect(mysql, NULL, NULL, NULL, "information_schema", 0, NULL, 0);
    MYSQL* con = mysql;
    string use="use ttddbb;";
    mysql_query_wrapper(con,use);
    string num = to_string(v);
    string s="insert into student values("+ num+",'zhangfei')";
    mysql_query_wrapper(con,s);
    return (void*)0;
}
int main(){
    //初始化, 只需要调用一次.
    init_mysql();
    assert(0 == mysql_thread_init());
    MYSQL* mysql = mysql_init(NULL);
    mysql_options(mysql, MYSQL_READ_DEFAULT_GROUP, "libmysqld_client");
    mysql_options(mysql, MYSQL_OPT_USE_EMBEDDED_CONNECTION, NULL);
    mysql_real_connect(mysql, NULL, NULL, NULL, "information_schema", 0, NULL, 0);
    MYSQL* con = mysql;
    string s;
    s="SELECT @@sql_safe_updates";
    mysql_query_wrapper(con,s);
    s="create database if not exists ttddbb;";
    mysql_query_wrapper(con,s);
    s="use ttddbb;";
    mysql_query_wrapper(con,s);
    s="create table if not exists student (id integer, name varchar(20));";
    mysql_query_wrapper(con,s);
    pthread_t pids[THREAD_NUM];
    int i;
    for (i = 0; i < THREAD_NUM; i++) {
        pthread_create(&pids[i], NULL, thread_func, (void*)(unsigned long)(i));
    }
     for (i = 0; i < THREAD_NUM; i++) {
        pthread_join(pids[i], NULL);
    }
    s="select * from student";
    mysql_query_wrapper(con,s);
    return 0;
}

```




#### 其他接口的补充


+ mysql_insert_id()

如果表格中定义了AUTO_INCREMENT的列, 则调用该函数可以返回表格中上一次插入的id.

这样, 对于多线程情况下, 调用MySQL embedded的基本使用就没有问题了. 对于单线程以及CS模式, 可以参考[3].

#### 参考文献

[[1] expert mysql]()
[[2] http://zetcode.com/db/mysqlc/](http://zetcode.com/db/mysqlc/)
[[3] http://zetcode.com/databases/mysqltutorial/](http://zetcode.com/databases/mysqltutorial/)
[[4] http://stackoverflow.com/questions/26936481/multithreaded-programming-with-libmysql/26936751#26936751](http://stackoverflow.com/questions/26936481/multithreaded-programming-with-libmysql/26936751#26936751)
[[5] http://dev.mysql.com](http://dev.mysql.com/doc/refman/5.7/en/mysql-library-init.html)
[[6] https://www.safaribooksonline.com](https://www.safaribooksonline.com/library/view/mysql-in-a/9780596514334/re422.html)

