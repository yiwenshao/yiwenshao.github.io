---
title: MySQL的UDF
date: 2016-11-20 12:55:29
tags: [MySQL,HelloWorld,UDF]
categories: database
---

最近用到MySQL的UDF, 查了一下相关文献, 对用户用户实现function和Aggregate function的方法做个介绍. 本文用到的代码可以在[https://github.com/yiwenshao/code_for_blog/tree/master/2017/5/MySQL%E7%9A%84UDF](https://github.com/yiwenshao/code_for_blog/tree/master/2017/5/MySQL%E7%9A%84UDF) 下载获得.

<!--more-->

### 快速编写一个MySQL UDF

为了能够快速了解UDF(user-defined function)是什么, 我们首先构建一个最简单的UDF, 然后再介绍更细节的内容. 本文在Ubuntu16.04下测试, 开始之前需要先安装MySQL以及相关的库, 在Ubuntu下是:

```
sudo apt-get install libmysqlclient-dev
```


#### Step1: 编写c++代码并生成动态链接库

示例c++代码如下:

```cpp
extern "c"{
long long myadd(UDF_INIT *initid, UDF_ARGS *args,
                char *is_null, char *error);
my_bool myadd_init(UDF_INIT *initid, UDF_ARGS *args,
                  char *message);
}

long long myadd(UDF_INIT *initid, UDF_ARGS *args,
                char *is_null, char *error) {
    int a = *((long long *)args->args[0]);
    int b = *((long long *)args->args[1]);
    return a + b;
}

my_bool myadd_init(UDF_INIT *initid, UDF_ARGS *args,
                  char *message){
    return 0;
}
```

完成以后, 将文件保存为udf.cpp 然后使用如下的命令编译动态链接库:
```
g++ -shared -fPIC -I /usr/include/mysql -o udf.so udf.cpp
```
获得udf.so文件.

#### Step2: 在MySQL中添加函数

完成上述的编写以后, 将udf.so文件拷贝到MySQL的plugin目录下, 在Ubuntu16.04中默认是:
```
/usr/lib/mysql/plugin/
```
然后使用如下的命令在MySQL中安装动态链接库. 

```
CREATE FUNCTION myadd RETURNS INTEGER SONAME 'udf.so'
```

#### Step3: 调用函数以及相关查询

+ 调用函数

```
select myadd(1,2);
```
可以获得计算结果3


+ 查询安装列表

```
select * from mysql.func;
```
可以查看数据库当前被安装的.so的库列表.

+ 用drop function来删除函数:

```
DROP FUNCTION myadd;
```


### UDF编写过程解释

可以看到, 我们在上面添加了自己的函数myadd, 这个函数被安装以后可以被MySQL执行. 我们同时定义了myadd\_init, 这是系统规定的必须使用的初始化函数. 在编写MySQL的UDF的时候, 一方面我们要定义自己需要的函数, 另一方面, 我们要同时编写配套的一系列其他函数, 这些函数的命名有固定规则. 比如用户自定义的函数名为xxx, 则配套的函数为xxx\_init, xxx\_deinit等, 其参数列表也是固定的,下面进行介绍. 


#### 编写用户主函数

首先是用户函数的定义, 我们假设需要定义的函数名字为为xxx, 则我们的函数需要有参数列表和返回值, 这不能由用户随意指定, 是有固定规则的. 

其中返回类型支持5种:

```
enum Item_result {STRING_RESULT=0, REAL_RESULT, INT_RESULT, ROW_RESULT,  DECIMAL_RESULT}; 
```

对于这5种返回值, 定义的函数头分别如下:


+ 返回值是STRING 类型或DECIMAL类型

```
char *xxx(UDF_INIT *initid, UDF_ARGS *args,
          char *result, unsigned long *length,
          char *is_null, char *error);
```

对于这种定义, 返回值可以指向result, 把需要的内容拷贝进去, 并设置长度, 如下:

```
memcpy(result, "result string", 13);
*length = 13;
```

+ INTEGER类型

```
long long xxx(UDF_INIT *initid, UDF_ARGS *args,
              char *is_null, char *error);
```


+ REAL类型

```
double xxx(UDF_INIT *initid, UDF_ARGS *args,
              char *is_null, char *error);
```

+ ROW类型

未实现


#### 编写系统内置函数

在完成了用户定义的主函数以后, 还需要编写配套的系统内置函数. 其相关说明如下:


##### xxx_init
这个函数会在自定义的xxx函数调用前被调用, 进行基本的初始化工作, 其完整定义如下:

````
my_bool xxx_init(UDF_INIT *initid, UDF_ARGS *args, char *message);
````

+ 返回值: 1代表出错, 可以在message中给出错误信息并且返回给客户端, 0表示正确执行.信息长度不能大于MYSQL_ERRMSG_SIZE
+ 函数功能: 该函数的主要功能一般是分配空间, 函数参数检查的等. 如果不需要做任何操作, 直接返回0即可.




##### xxx_deinit
该函数用于释放申请的空间, 其完整定义如下:
```
void xxx_deinit(UDF_INIT *initid);

```

+ 函数功能: 该函数的功能主要是释放资源, 如果在xxx_init中申请了内存, 可以在此处释放, 该函数在用户函数xxx执行以后执行


对于普通的UDF, 上面两个内置函数足够了, 但是对于Aggregate函数, 像sum, count函数, 必须额外给出如下的函数:

##### xxx_clear

其完整定义如下:

```
void xxx_clear(UDF_INIT *initid, char *is_null, char *error);

```

##### xxx_add

```
void xxx_add(UDF_INIT *initid, UDF_ARGS *args,
             char *is_null, char *error);
```


#### 两种UDF的执行流程介绍

这两种UDF非别有如下的执行流程:

##### 普通函数执行流程

+ 调用xxx_init来初始化, 并申请内存空间用于存储结果
+ 调用xxx
+ 调用xxx_deinit释放空间

对于普通函数的执行流程, 可以参照一开始给出的myadd函数.

##### Aggregate函数执行流程

+ 调用xxx_init来初始化, 并申请内存空间用于存储结果
+ 对表使用group by 排序, 形成多个或一个group
+ xxx_clear调用, 对每个新的group, 调用之
+ 对每个group的每一行,调用xxx_add
+ 调用xxx
+ 重复3-5, 直到处理完所有的group
+ 调用xxx_deinit释放空间

对于Aggregate函数的执行流程, 可以参照后面给出的mysum函数.

#### 函数参数列表介绍

对于上面介绍的函数, 其参数列表和返回值是我们所关注的, 对于某些函数特有的参数, 在上面介绍函数的同时已经做了介绍, 现在介绍其公有的参数部分:

##### UDF_INIT

该结构主要用于用户函数与系统内置函数的通信, 其结构如下:

|成员|作用|
|-|-|
|my_bool maybe_null|其值为1表示函数可以返回NULL, 默认值是1|
|unsigned int decimals|参数如果是小数, 表示小数点后面的位数|
|unsigned int max_length|返回结果的最大长度|
|char *ptr|用户可以申请自己的内存空间, 然后用这个指针指向自己的空间供自己的函数使用|
|my_bool const_item|如果用户函数对于相同输入总有相同输出, 则其值为1, 这是默认值. 否则则设置为0|

在本文例子中, 我们只用到ptr, 其余均使用默认值. 所谓的通信, 是指我们在xxx_init中就有这个参数了, 后后续的xxx与xxx_deinit中, 我们依然可以获取这个类型的指针, 这样, 我们就可以在xxx_init函数中申请一块空间, 并令ptr指向这块空间, 在xxx函数中使用这块空间, 然后在xxx_deinit中释放空间, 这是MySQL的UDF的基本用法. 


##### UDF_ARGS

该结构主要用于传参数, 参数由MySQL提供, 对于表而言, 就是一行一行的表数据, 其介绍如下:

|成员|作用|
|-|-|
|unsigned int arg_count|函数参数的个数, 可以在xxx_init函数中通过这个成员对用户输入的参数个数进行检查, 如果参数个数错误, 则不执行或返回错误|
|enum Item_result *arg_type|参数的类型, 可以在这不做参数类型的检查, 也可以自己强制指定类型,类型有5种, 在前一小节已有说明|
|char **args|如果参数是STRING_RESULT类型,可以通过args->args[i]来获取内容, 通过args->lengths[i]来获取长度; 如果是 INT_RESULT可以通过int_val = *((long long*) args->args[i]);来获取内容  REAL_RESULT或者STRING_RESULT类型可以通过real_val = *((double*) args->args[i]);来获取内容|
|unsigned long *lengths|对于初始化函数, 保存了参数的最大长度. 对于用户定义的主函数, 保持了各个参数的长度, 这个对于string类型有用, 因为这里的string不一定是'\0'结尾的|
|char *maybe_null|其值为0表示一个参数不能是null, 1表示可以|
|char **attributes|可以获得参数的名字.比如SELECT my_udf(expr1, expr2 AS alias1, expr3 alias2);则args->attributes[0] = "expr1" args->attribute_lengths[0] = 5 后面同理 |
|unsigned long *attribute_lengths|每个参数名字的长度|

可以看到, 这个参数结构提供了很多功能, 本文只关注通过args成员来获得具体的参数内容.




#### 一个Aggregate 函数的例子

有了上面的基础, 我们就可以自己实现一个sum函数mysum, 其作用和内置的sum有一样的功能, 下面给出代码和解释:
```
#include <mysql/mysql.h>

extern "C" {
my_bool   mysum_init(UDF_INIT *const initid, UDF_ARGS *const args,
                           char *const message);
void mysum_deinit(UDF_INIT *const initid);
void mysum_clear(UDF_INIT *const initid, char *const is_null,
                            char *const error);
void mysum_add(UDF_INIT *const initid, UDF_ARGS *const args,
                          char *const is_null, char *const error);
long long mysum(UDF_INIT *const initid, UDF_ARGS *const args,
                      char *const result, unsigned long *const length,
                      char *const is_null, char *const error);
}



//执行前先进行初始化,分配空间
my_bool mysum_init(UDF_INIT *const initid, UDF_ARGS *const args,
                           char *const message){
    long long * i = new long long;
    initid->ptr = (char*)i;
    return 0;
}

//在执行该函数前,先执行group by, 然后遇到每个新的group, 先调用该函数.如果没有group by, 则所有的都是一个group.
void mysum_clear(UDF_INIT *const initid, char *const is_null,
                            char *const error) {
    *((long long *)(initid->ptr)) = 0;
}

//每一行数据都经过add函数处理
void   mysum_add(UDF_INIT *const initid, UDF_ARGS *const args,
                          char *const is_null, char *const error) {
    *((long long *)(initid->ptr)) =  *((long long *)(initid->ptr)) +
                                    *((long long *)args->args[0]);
}

//所有数据处理完成, 调用用户定义的mysum函数返回结果;遇到下一个group, 重新从clear开始执行.
long long mysum(UDF_INIT *const initid, UDF_ARGS *const args,
                      char *const result, unsigned long *const length,
                      char *const is_null, char *const error) {
    return *((long long *)(initid->ptr));
}

//执行结束, 释放空间
void mysum_deinit(UDF_INIT *const initid){
    
    delete initid->ptr;
}



```

使用上述的方法编译并复制到对应的plugin目录以后, 可以用如下的命令添加函数, 注意这里和添加普通的函数方法不一样.

```
CREATE AGGREGATE FUNCTION mysum RETURNS INTEGER SONAME 'udf.so';

```

函数执行结果如下:

```
Database changed
mysql> select * from student;
+------+-----------+
| id   | name      |
+------+-----------+
|    1 | zhangfei  |
|    2 | zhangfei  |
|    3 | zhangfei  |
|    4 | zhangliao |
|    5 | zhangliao |
|    6 | zhangliao |
|    7 | shaoyiwen |
+------+-----------+
7 rows in set (0.00 sec)

mysql> select mysum(id) from student;
+-----------+
| mysum(id) |
+-----------+
|        28 |
+-----------+
1 row in set (0.00 sec)

```

### 总结

可以看到, MySQL的UDF可以用于处理MySQL表中的数据, 其对外提供了普通函数与Aggregate函数接口, 普通函数处理一行的数据, Aggregate函数处理一个group的数据. 其函数头是固定的, 对外提供了5种数据类型.需要注意的是, 我们编写的MySQL UDF必须保证是线程安全的.

### 相关资料

[[1] http:/dev.mysql.com/doc/refman/5.7/en/adding-udf.html](http:/dev.mysql.com/doc/refman/5.7/en/adding-udf.html)
[[2] http:/blog.csdn.net/luoqiya/article/details/12888553](http:/blog.csdn.net/luoqiya/article/details/12888553)
[[3] http:/www.codeproject.com/Articles/15643/MySQL-User-Defined-Functions](http:/www.codeproject.com/Articles/15643/MySQL-User-Defined-Functions)

