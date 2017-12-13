---
title: Hbase概述
date: 2016-12-04 15:37:02
tags: Hbase
categories: database
---

本文对最近接触到[Hbase](https://hbase.apache.org/)相关的资料做个简单整理, 主要包含了数据模型, 底层存储结构, 以及分布式模型.Hbase是Google发表的论文Bigtable的开源实现, 文中对于BigTable和Hbase中的对应的名词在不引起歧义的情况下可能混合使用, 不做区分. 

<!--more-->

部分可能替换如下:

|Hbase|BigTable|
|-|-|
|Region Server/Data Node|Tablet Server|
|Region|Tablet|
|MemStore|Memtable|
|StoreFile|SStable|


#### 数据模型
数据模型在这里是指数据库对外提供的抽象的数据操作模型, 不涉及底层的存储, 在有些资料也叫概念视图. 例如对MySQL来说, 我们可以建立一个多列的表格, 每列可以指定属性, 那么**表**就是MySQL的数据模型, 相应的, 对于Redis, 数据模型是KV(Key-Value), 用户可以进行简单的Key-Value的操作. Hbase的数据模型是也是表, 但是这个表和关系型数据库中的表有所不同. 它是一个稀疏表. 在这个表中, 用户可以定义一些列族(Column Family), 每个列族下面可以定义列名(Column qualifier), 然后每行的数据可以定义行键(Row Key), 通过指定唯一的行键以及相应的列族和列名, 就可以找到一个最小的存储单元, 称为Cell.  每个Cell中有保存了数据的多个版本, 每个版本有一个时间戳(timestamp). 所以, 有些资料也把Hbase的数据模型看成是一个KV结构, Key是四维的元组(Column key,Column Famliy, Row Key, timestamp), Value是一个字符串.

我们给出一张图来说明为什么是稀疏表以及KV结构.

{% asset_img Picture1.png t %}

[图片取自: http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx](http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx)

这是Bigtable论文中的一张图, 其解释了Hbase的数据模型. 和关系型的表中直接指定每列的属性名和属性这种方式不同, 这里我们的列首先有用户预先指定的一些Column Family, 在Column Family的基础上, 进一步指定Column Key 作为列的名字. 用户插入数据, 需要指定Row Key, Column Family, 以及Column Key, 然后就可以在一个Cell中存一个字符串型的Value. 但是, 这个插入到此为止, 这一个大表中的其他列不需要因为这条插入而增加数据, 而这关系型表结构中, 一次插入一行数据, 当前行的每列都需要有数据, 这也就是两种表结构的区别, 所以其数据模型可以看成一个稀疏表.

#### 索引与数据放置

Hbase根据行键来建立索引, 按照列来进行数据存储, 这里首先简单说明行存储和列存储:

* 行存储:  行存储是(行　行　行)这种形式存满磁盘页, 这样如果只有部分属性是有用的, 就会造成带宽浪费, 因为读取了很多没有用的列. 传统的关系型数据库, 使用了行存储的方式. 
* 列存储: 列存储适合于需要一次读取部分列数据的操作, 如常见的数据分析场景(对某列求平均等操作), 但是其Join操作要读取不同的磁盘页, 代价比较大. 本文参考的课程的一个作业就是在Hbase上实现Join操作. Hbase不是严格的列式, 因为是列族层次的列,不是每个小列.

对于Hbase的一个表来说, 其有很多的列族, 不同的列族分开在不同的文件中进行存储. 同一个列族存在一起, 列族下面的列可以动态增加. 对于时间戳,如果没有给出参数, 查询的时候返回的是最新的版本. 提供了保留历史的n个版本和保留最近n天的版本两种方案.

行键是字符串, 存成字节数组, 根据字典序排序, 提供了直接访问, 范围访问, 和全表扫描三种访问的方式. 其关注的要点如下:

+  列族数量不能太多, 一般就几十个. 并且要建表的时候就创建好. 列族可被设置成放入到内存中, 从而消耗内存换取更好的性能.

+ 列限定符(Column Key)没有数据类型, 不要事先定义, 被当成byte\[\]

+ Cell的数据类型也是byte\[\]

+ Timestamp是64位整数


从逻辑上来讲, 一个Row-Key 对应一行的数据, 每行可以有很多的Column Famliy以及Column Key, 对应就是一个数据单元cell, 其内部可以有好多的不同版本的数据, 对应多个TimeStamp.

从物理上来讲, 按照列族来存储表格, 每个都是Row Key 建立索引, 在大表概念图里面可能遇到了空值, 但是这个不是被存储成null, 而是直接不存, 查不到就是返回null. 

#### Hbase的分布式架构

Hbase的分布式采用了Master Slave 结构, 支持水平扩展, 下图就是一个典型的Hbase 概念图.

{% asset_img HBase-Cluster.png t %}
[图片取自Google Image](https://www.google.com/search?q=Hbase+master+slave&newwindow=1&biw=1244&bih=548&source=lnms&tbm=isch&sa=X&ved=0ahUKEwis-PXHzdnQAhXKoJQKHcaWCRQQ_AUIBygC#imgrc=TpOlagyC8mMUGM%3A)


Hbase NameNode是Master, 用于保存元数据, Slave是多个Data Node, 用于保存实际的数据.  由上一小节可知, 我们的数据模型是一个大表, 实际存储是按照列族分开存. 对于实际存储数据的DataNode而言, 表是按照Row Key排序, 然后被划分成不同的Region, 分给不同的DataNode. Master来负责这个分配工作并进行记录, 列族和表的创建, 以及某个Region Server跪了以后把它的Region分给其他人DataNode. 


Master虽然有这些元数据信息, 但是Hbase客户端不直接通过Master获得这个信息, 而是通过[zookeeper](https://zookeeper.apache.org/)来获得这个信息, 这就是上图中的Zookeeper的作用. 

我们刚开始建立一个表的时候后, 表只有一个Region, 并且其中的项目是按照Row Key 排好序的. 后来随着数据不断插入, 表变比较大了, 就需要进行拆分, 变成多个Region, 然后不同的Region分到不同的Server上, 一般一个Server管10-100个Region, 每个Region的默认大小是100M到200M, 这个可以用户进行配置. 

这样, 对于表中的一行数据来说, 如何进行定位呢? 

首先对于每个Region Server, 有自己的region id, 那么一个表中的Region的标识的方法就可以是**(表名+开始的row key+region id)**, 这样, 我们的任意一个表中的任意一个Region都有唯一的标识. 这个Region和和具体机器之间的映射关系是保存为.META表, 通过查询这张表, 就可以找到表中的Region对应的机器的IP, 从而和具体的机器交互获取数据. 

如果.META表项目非常大, 也会分布存储, 然后用一个不可分割的-ROOT表来记录这些不同的Region的.Meta表. 所以此时, 查找策略是从ZooKeeper中获得Root的位置, 从而找到.META的位置, 从而进一步找到对应的机器的IP地址, 从而能够找到特定的机器, 然后根据行键建立的索引来找到需要的数据项. 


.META表也是Hbase中的表, 其特点是每个Region都在内存中, 假设一个Region128M, 每个项目是1KB, 由于一个root表只能一个Region 128M, 所以最多可以存储$$128M/1K × 128M/1K =2^{34}$$  个Region. 这里的Root和.META表组成三层类似B+树的结构. 

有了以上的总体概念, 我们进一步考虑每个系统模块的细节工作, 包括单机的Data Node的数据存储方式. 


#### 系统模块的总结

我们以一个Hbase中典型的数据插入和查询操作, 来解释各个系统模块的作用. 我们从客户端发出一个查询命令的, 所以首先介绍Hbase的客户端. 

##### Client

Client通过RPC来和Master以及DataNode(Region Server)进行交互, 其中和Master的交互主要完成一般的管理操作, 和DataNode进行交互主要进行一般的数据处理操作. Hbase提供了多种客户端接入的方式, 如下:

+ Java API: 也就是通过Java库来完成Hbase的接入

+ Hbase Shell: 交互式的操作, 类型于MySQL的交互式Shell

+ Thrift

+ Rest

+ Pig

+ Hive

本系列相关的文章主要关注使用Java库接入的方式. 


##### ZooKeeper

ZooKeeper主要用于分布式集群管理, 每个Region都要在ZooKeeper进行注册,  其可用于通知Master每个Region的状态, 还可以帮助选择Master, 保证只有一个Master, 同时, 其保持了Root表, 表和列族信息, 以及Master的位置信息. Client要获得元数据, 不会直接和Master通信, 而是通过ZooKeeper来完成. 更多ZooKeeper的内容, 请关注本系列后续文章. 

##### Master
ZooKeeper 和Master交互,可以获取元数据. Master负责进行Region 分配, 表的元数据管理, 负载均衡等工作.

##### Region Server

经过上面的步骤, 我们的Client就可以通过RPC和具体的Region Server(Data Node)交互, 获取实际的数据了. 这里介绍Region Server的主要结构. 
{% asset_img RegionServer.png t %}
[图片取自: http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx](http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx)


由上面的小结可知, Region Server底层使用HDFS来进行数据处理, 其内部存储了很多的Region对象, 这些Region对象来自于我们建立的大表的拆分. 我们现在以一个Region为基本单位进行介绍.

一个Region内部有很多的Store, 每个Store对应不同的列族. Store里面包含了MemStore, 以及StoreFile, 前者是内存的缓存, 保存最近的数据, Storefile是排序好的磁盘文件, Storefile通过HDFS的HFile实现.

写数据的时候, 先写缓存以及HLog, 然后定期flush到磁盘中, 变成一个StoreFile. 刷新会在Log中有记录,  Log检查的时候, 看Log里面flush以后有没有新的数据写入, 如果有, 就写入到memstore中, 然后flush到磁盘. Storefile比较多的时候, 会造成查询慢, 所以设置阈值定期合并StoreFile.

上面的Log又称为Write Ahead Log, 也就是先写Log再写MemStore, 并且保证Log总是先于MemStore中对应的项目被刷新到磁盘中, 这种机制保证了写入磁盘的操作都是在Log中有记录的. Log只有一个, 所以故障的时候, Master要分析Log里面的不同的Region, 进行故障处理. 这样的好处是只要追加一个文件, 不要多个文件, 减少了磁盘的寻址次数. 

对于Store, MemStore满了, 就flush变成StoreFile, StoreFile多了就合并, 如果大了就分裂, 会触发表格分成不同的Region, 然后进行Region的分配.


#### 总结

Hbase是一个分布式的数据库系统, 其分布式的模型是Master Slave结构, 通过ZooKeeper来完成集群同步. 数据模型是稀疏表, 也可以看成Key-Value结构. 其使用Master来管理元数据, 通过表中的Row建立索引.  数据存储采用了面向列族的方式, 每个表根据Row Key进行排序, 然后分成不同的Region 进行存储. 每个Region存在一个Region Server上. 对于Region的处理, 首先根据列族分成了不同的Store, 对于每个Store, 在内存的区域采用了Memtable, 磁盘采用了StoreFile. 写入的时候, 先写Log以及内存, 当Memtable住够大的时候, 排序刷入磁盘. 


以下附上Hbase和传统的关系型数据库的简单对比:

||Hbase|RDBMS|
|-|-|-|
|索引|基于Row Key建立索引|运行用户基于不同的列自行建立复杂的索引|
|数据模型|稀疏表, 使用了字符串作为数据格式, 用户负责数据格式处理|使用了关系型的表结构, 提供了多种数据格式如整数, 日期, 字符串等|
|数据操作|基于Row Key进行增删改查, 不支持表间的操作, 不支持跨行的Transaction|支持基本的增删改查, 还支持表间的Join等操作, 支持跨行的Transaction|
|存储模式|列存储|行存储|


#### 相关文献

[1. Hbase a difinitive Guide]()

[2. Bigtable: A Distributed Storage System for Structured Data. Fay Chang, Jeffrey Dean, Sanjay Ghemawat, et al. (Google). OSDI 2006]()

[3. 大数据技术原理与应用 林子雨 人民邮电出版社]()

[4. 国科大课程材料: 大数据系统与大规模数据分析  陈世敏]()

[5. http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx](http://web.cs.wpi.edu/~cs525/s13-MYE/lectures/5/HBase.pptx)

[6. O’N EIL , P., C HENG , E., G AWLICK , D., AND O’N EIL ,E. The log-structured merge-tree (LSM-tree). Acta Inf. 33, 4 (1996), 351–385.]()

