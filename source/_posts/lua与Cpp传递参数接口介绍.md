---
title: lua与Cpp传递参数接口介绍
date: 2016-12-11 17:32:55
tags: [lua,C++,虚拟栈]
categories: helloworld
---

最近在开源代码中遇到MySQL-Proxy, 其允许lua脚本实现用户的个性化配置, lua脚本可以引用C/C++的动态链接库完成一些复杂的功能. 本文对最近接触到的lua和C/C++混合的相关接口使用做个总结. 本文的完整代码在文末的附录中, 代码测试在Ubuntu16.04+lua5.1下完成, 不同版本可能API有所变化, 可以参考文末给出的官方文档链接.

<!--more-->
#### 相关环境配置

首先, 要在C++中使用相关的lua的工具, 需要lua.hpp这个头文件. 在Ubuntu下, 首先需要安装lua, 然后可以在/usr/include 目录下找到相关的头文件. 其他系统可能有所不同, 可以根据具体的头文件来进行设置, 完成这步以后, 就可以开始写相关程序.

```
//Ubuntu16.04下的环境配置
sudo apt-get install lua5.1
```


#### HelloWorld

##### HelloWorld程序

为了能够快速了解怎么混合使用C++和lua, 这一小节先实现一个最简单的helloworld来了解整个程序的结构, 以及相应的需要注意的点, 然后介绍具体细节. 

首先, 我们的目标是提供一个firstFile.so动态库文件, 给我们的lua脚本使用. 于是, 我们新建一个文件**test.cpp**, 写入以下内容.

```
#include<lua5.1/lua.hpp>
#include<lua5.1/lualib.h>
#include<lua5.1/lauxlib.h>
#include<iostream>
extern "C" int luaopen_firstLib(lua_State *L);

int InternalHello(lua_State* L) {
    std::cout<<"Hello World!"<<std::endl;
    return 0;
}

int luaopen_firstLib(lua_State *L){
    static const luaL_reg Map[]={
        {"look",InternalHello},
        {NULL,NULL}
    };  
    luaL_register(L,"first",Map);
    return 1;
}
```
然后使用如下的命令编译动态链接库firstLib.so
```
g++ -fPIC -shared -o firstLib.so test.cpp -llua5.1
```
如果上面的配置环境没有错误的话, 这段代码应该正常编译, 并形成firstLib.so库文件.

我们使用**lua look.lua**命令执行如下的脚本, 就可以获得HelloWorld输出:

```
package.cpath = "./?.so"
require "firstLib"
first.look()
```

#### HelloWorld的解释

我们现在对上面的helloworld做一定的解释, 如下:

+ 首先, 要编写一个**firstLib.so**, 我们需要在C++文件中编写对应的函数**luaopen_firstLib**.这个函数的名字是和库文件的名字**对应**的, 且返回值是int, 参数列表是lua_State\*. 

+ 需要为luaopen_firstLib函数添加extern "C"做声明.

+ 在luaopen_firstLib函数中, 可以注册自己库中希望对lua脚本提供的函数. 注册的方法如下:

```
int luaopen_firstLib(lua_State *L){
    //1. 使用luaL_reg array类型进行注册
    static const luaL_reg Map[]={
    //2. 左边是字符串,表示对外提供的函数名. 右边是自己内部实现的函数名
        {"look",InternalHello},
   //3. 以NULL,NULL结尾
        {NULL,NULL}
    };  
    //4. 调用注册函数, 其中first表示对外提供的库的名字
    luaL_register(L,"first",Map);
    return 1;
}
```

这里需要注意几个命名的规则:

+  我们需要的库文件的名称是firstLib.so, 所以需要编写luaopen_firstLib函数做初始化

+ 每个函数在c++文件中有一个名字(如InternalHello), 在注册给lua脚本用的时候, 可以指定另外一个名字(如look)

+ 注册的时候, 可以给自己的库起名字, 比如first

lua中使用动态库的代码注释如下:

```
--指定lua寻找动态库的路径
package.cpath = "./?.so"
--设置动态库, 并且调用luaopen_xxx函数进行初始化, 这里firstLib和库文件的名字对应
require "firstLib"
--执行动态库中提供的函数, 这里的库引用和自己注册的时候提供的库名字对应
first.look()
```

对于自定义的函数, 其函数的返回值和参数列表是固定的, 不能改变, 如下:

```
int (*lua_CFunction) (lua_State *L);
```

至此, 命名规则介绍完成, 我们可以编写任意的函数, 命名任意的库, 并且在lua脚本中进行调用. 剩下的部分, 就是传递参数了.

#### lua与c++传递参数
我在在C++中定义的函数只有一个参数, 即lua_State\*, 我们需要通过这个参数来完成所有的参数传递, 以及传递返回值的功能, 这个功能基于lua的虚拟栈,并且需要使用一系列配套的函数来完成. 关于虚拟栈, 先可以简单理解成一个数组空间, lua要传参数给C++函数时, 就把数据放在这个数组中, C++函数从这个数组中读取数据. C++函数要返回数据时, 也把数据放在这个数组中, 这样lua脚本可以读取返回的数据, 所以虚拟栈就是两边通信的管道.这个虚拟栈可以通过下标访问,下表从1开始,1表示栈底.也可以接受负数的下标,-1表示栈顶. 后面小结将对其做具体介绍, 我们首先考虑从C++函数中返回内容给lua脚本的情况.



##### 返回值
返回值可以使用如下的配套参数:

```
void lua_pushnumber (lua_State *L, lua_Number n);
void lua_pushnil (lua_State *L);
void lua_pushinteger (lua_State *L, lua_Integer n);
void lua_pushboolean (lua_State *L, int b);
void lua_createtable (lua_State *L, int narr, int nrec);
...
```
其中对于普通内置类型, 只要使用固定的函数就可以了, 官方文档的描述也比较详细, 代码可以参考文末的附录. 下面只考虑如何传table(表)类型.需要注意的是, 每个函数结束的时候, 有一个int类型的返回值, 这个返回值表示该函数返回给lua脚本的参数个数.如果返回值和实际入栈的参数不同, 就会出现错误.

对于table类型, 有两种情况, 一种是一维的表, 其结构如下

|key|value|
|-|-|
|k1|v1|
|k2|v2|
|k3|v3|

可以看到, 这就是普通的lua中的一维key-value结构表, 要在C++函数中产生这样的表并返回, 需要经过以下的步骤:

首先, lua_createtable函数可以创建一个新表, 然后把其作为单个参数放到栈中. 这样, 栈中就增加了一个元素, 剩下的工作就是向表里面添加kv对. 比如要往一个表中添加4个kv对, 可以写如下的函数:

```
static void mylua_pushtable2(lua_State *const l){ 
--建立新的一维表, 入栈, 表中有4个kv对, 第二个参数设置为0, 第一个参数是lua_state*
    lua_createtable(l,0,4);
--依次插入四个kv对, 先设置value, 然后设置key
    lua_pushstring(l,"v1");
    lua_setfield(l,-2,"k1");

    lua_pushstring(l,"v2");
    lua_setfield(l,-2,"k2");

    lua_pushstring(l,"v3");
    lua_setfield(l,-2,"k3"); 

    lua_pushstring(l,"v4");
    lua_setfield(l,-2,"k4");
}
```
上面调用的函数setfield中的-2, 表示下标-2的参数, 也就是我们建立的table,现假设其名字是tableA,则 setfield达到的效果是,tableA["key"]=top, 其中top是当前栈顶元素,并且同时栈顶元素出栈. top在这里正好就是v1.于是, 我们可以通过这样的方法设计一维的表返回. 如果需要key为int类型, 可以用lua_rawseti函数, 其函数签名如下:
```
https://www.lua.org/manual/5.1/manual.html#2.8
void lua_rawseti (lua_State *L, int index, int n);
```
更多的函数介绍, 可以看官方文档.



还有一种情况是多维的表, 也即嵌套的表, 给出如下的例子:

```
myTable = {
    [0] = { ["field1"] = 1, ["field2"] = 2,["field3"] = 3 },
    [1] = { ["field1"] = 10, ["field2"] = 20,["field3"] = 30 }
}
```

返回嵌套表的实例代码如下:

```
static void mylua_pushMultiTable(lua_State *const L){ 
    lua_createtable(L, 2, 0); 

    lua_pushnumber(L, 1); 

        lua_createtable(L, 0, 3); 

        lua_pushnumber(L, 1); 
        lua_setfield(L, -2, "field1");

        lua_pushnumber(L, 2);
        lua_setfield(L, -2, "field2");

        lua_pushnumber(L, 3);
        lua_setfield(L, -2, "field3");

    lua_settable(L, -3);

    lua_pushnumber(L, 2);
        lua_createtable(L, 0, 3);

        lua_pushnumber(L, 10);
        lua_setfield(L, -2, "field1");

        lua_pushnumber(L, 20);
        lua_setfield(L, -2, "field2");

        lua_pushnumber(L, 30);
        lua_setfield(L, -2, "field3");

    lua_settable(L, -3);
}
```
可以看到, 对于一个key对应内部value结构是一个表的情况, 需要用到lua_createtable的第二个参数, 表示最外层需要的项目个数.对于内部的每个表, 则再次使用建立一维表的方式来完成kv对的插入, 这里的lua_settable的作用和上面介绍的lua_setfield相似. 对于我们例子中的表, 外层有两个项目,key分别是0和1, 所以lua_createtable的第二个参数设置为2. 对于内层的表, 由于有三个项目, 所以lua_createtable的第三个参数设置为3.

##### 接受参数

接受从lua脚本中传递的参数可以使用如下的函数:

```
int lua_toboolean (lua_State *L, int index);
double lua_tonumber (lua_State *L, int index);
lua_Integer lua_tointeger (lua_State *L, int index);
const char *lua_tolstring (lua_State *L, int index, size_t *len);
int lua_next (lua_State *L, int index);
....
```

可以看到, 接受参数需要用户显式指定下标和数据类型, 这样lua传递过来的数据才能正确解析.

+ 传string类型
lua传string类型是以const char \* 来传递的, 是一个一'\0'结尾的c字符串. 在返回字符串的时候, 同时可以获得字符串的长度.可以使用如下的简单封装来直接获取C++中的std::string类型.

```
static void
mylua_pushlstring(lua_State *const l, const std::string &s) {
    lua_pushlstring(l, s.data(), s.length());
}
```
+ 传double类型
+ 传bool类型
对于bool和double类型, 比较直接, index表示栈的位置, 通过下标就可以直接访问参数了. 下面介绍一下如何处理lua调用方传送过来的table类型.

+ 传array类型
在lua中, array是一种特殊table, 其key值分别是1 2 3 4... 我们尝试在lua中构造一个如下的array, 并且通过函数进行传递:

```
para2={ "1","SHAOYIWEN","CS" }
```

lua提供了一般形式的array传值模板, 我们假设传过来的array下标是t, 其解析的C++代码如下:

```
lua_pushnil(L);
while (lua_next(L, t) != 0) {
printf("%s - %s\n",
      lua_typename(L, lua_type(L, -2)),
      lua_typename(L, lua_type(L, -1)));
lua_pop(L, 1);
}
```

在上面的代码中, lua_next函数每次调用, 就会从当前虚拟栈中弹出一个值, 然后从下标指定的table变量中取出一个kv对, push到栈上. 如果table中没有kv对了, lua_next就返回0. 所以, 我们在调用lua_next前, 先在栈中push一个nil, lua_next调用的时候, 正好将这个值弹出栈, 然后在栈中添加一个kv对. 这样-2下标可以得到key, -1下标可以得到value. 使用完成以后, 主动pop一个值, 进入下一个循环, 直到table中的数据全部读取完. 

+ 传table类型
对于普通的一维table, 直接使用和array一样的方式就可以了. 对于嵌套的table, 其实就是单维table的组合, 现给出一个例子.

我们在嵌套的table中存了这样的数据, 并将其通过函数传送给c函数.

```
para4={["k1"]={["ik1"]="v1",["ik2"]="v2"},["k2"]={["ik1"]="v11",["ik2"]="v22"} }

```
那么, 在c代码中, 假设这个是第四个参数, 我们可以通过如下的代码嵌套的table类型. 

```
static std::string
mylua_tolstring(lua_State *const l, int index)
{
    size_t len;
    char const *const s = lua_tolstring(l, index, &len);
    return std::string(s, len);
}

lua_pushnil(L);
while(lua_next(L,4)) {
    //获取外层的key
    std::string key = mylua_tolstring(L,-2);
    lua_pushnil(L);
    //value是一个table类型,此时下标是-2,故而用一位table解析的模板处理
    while(lua_next(L,-2)){
      std::string ikey = mylua_tolstring(L,-2);
      std::string ivalue = mylua_tolstring(L,-1);
      std::cout<<"ikey: "<<ikey<<"  ivalue: "<<ivalue<<std::endl;
      lua_pop(L,1);
   }
   lua_pop(L,1);
}
```
可以看到, 对于一维的array的情况, 我们调用的lua_next以后, 栈上有一对kv, key和value都是基础类型. 而对于多维表的情况, value依然是一个table类型, 所以处理的方法就是再进行一个层次的lua_next调用, 把table类型的value解析出来. 至此, 我们已经可以在lua和c++之间传递基础数据类型, 一维表类型, 以及嵌套表类型这三种数据了. 

##### lua虚拟栈机制

现在我们已经知道了lua和C/C++如何相互传参数, 接下来简单介绍一下其基本原理. 我们知道, 在一般情况下, c语言本身的函数调用是通过栈来传递参数的. lua和C/C++的参数则是通过lua虚拟栈来进行参数传递. 栈中可以存lua参数. lua的每次C/C++函数调用, 都会建立新的虚拟栈, 这个栈也是C/C++函数返回参数必须用到的. 这个虚拟栈支持下标访问. 从栈底开始由1编号, 也接受负数的下表, -1代表栈顶, -n代表栈底. 需要注意的是, 这个栈的下表访问不收C/C++内部函数调用的影响, 也就是说, 我们通过lua调用了动态库中的函数A, 函数A进一步调用了内部的函数B, 这不会影响栈中参数的下标.

lua的栈默认支持最大下标20的访问, 如果需要更多的空间, 则可以通过lua_checkstack函数进行空间申请.

对于参数的传递, 其中lua调用函数的时候, 参数是从左到右的顺序以此入栈的. 这也就是编号1可以获得第一个参数的原因. 参数返回的时候, 第一个参数先入栈, 并且最后返回参数的个数, 这样lua调用方就知道获取几个参数. 栈中剩余的内容会在调用以后被清除.



#### 总结

我们可以看到, lua和C++通过虚拟栈的机制来通信, 完成了值传递过程. 对于函数的多个参数, 其约定好了参数入栈的顺序, 对于返回值, 其直接通过return一个整数来告诉lua脚本返回了多少个参数. lua和C++的数据类型系统并不一致, 所以lua提供了配套的函数进行数据类型的转换. lua数据可以转换到C++中的double,int,bool等类型. 对于C中没有的表类型, 则是通过虚拟栈以及lua_next配套函数, 提供具体到表中每个值的访问, 这样用户就可以在C++中处理复杂的嵌套表数据结构了.



#### 附录

##### 调用库的另外一种方法
要使用动态库, 除了使用require以外, 还可以使用package.loadlib.事实上, lua的require就是基于package.loadlib实现的. 具体可以看参考文献, 下面给出一个简单的例子:

```
-- 加载动态链接库, 并进行链接, 返回f是函数的句柄
f=package.loadlib("./firstLib.so","luaopen_firstLib")
-- 如果返回成功, 则可以通过句柄调用luaopen_firstLib函数
if f then
    f() 
else
    io.write("error")
end
--注册完成以后, 可以使用任意的函数
first.look()
```
由此我们也可以知道, luaopen_firstLib作为初始化函数并不是必须的, 只是在我们使用require的时候, 这样命名能够实现自动初始化. 但是我们如果使用底层的loadlib函数, 则可以指定任意名字的函数来实现初始化函数注册的工作, 这样就不一定需要写luaopen__xxx函数了;


##### 相关程序完整代码

给出我测试过程中使用到的一些测试程序完整代码共参考


+ 完整的测试代码test.cpp

```
#include<lua5.1/lua.hpp>
#include<lua5.1/lualib.h>
#include<lua5.1/lauxlib.h>
#include<iostream>
#include<string>
extern "C" int luaopen_firstLib(lua_State *L);
extern "C" int InternalHello(lua_State* L);

static std::string
mylua_tolstring(lua_State *const l, int index)
{
    size_t len;
    char const *const s = lua_tolstring(l, index, &len);
    return std::string(s, len);
}

static void StackPrint(lua_State *L, const char * Str) {
    int J, Top;
    Top = lua_gettop(L);
    std::cout<<"Top: "<<Top<<std::endl;
    printf("%-26s [", Str);
    for (J = 1; J <= Top; J++) {
        if (lua_isnil(L, J)) printf("-\t");
        else std::cout<<mylua_tolstring(L,J)<<"\t";
    } 
    printf("]\n");
}

static void
mylua_pushlstring(lua_State *const l, const std::string &s) 
{
    lua_pushlstring(l, s.data(), s.length());
}

static void mylua_pushtable(lua_State *const l){
    lua_createtable(l,0,4);

    lua_pushstring(l,"v1");
    lua_setfield(l,-2,"1");

    lua_pushstring(l,"v2");
    lua_setfield(l,-2,"1");

    lua_pushstring(l,"v3");
    lua_setfield(l,-2,"3"); 

    lua_pushstring(l,"v4");
    lua_setfield(l,-2,"4");
}

static void mylua_pushMultiTable(lua_State *const L){
    lua_createtable(L, 2, 0);

    lua_pushnumber(L, 1);

        lua_createtable(L, 0, 3);

        lua_pushnumber(L, 1);
        lua_setfield(L, -2, "field1");

        lua_pushnumber(L, 2);
        lua_setfield(L, -2, "field2");

        lua_pushnumber(L, 3);
        lua_setfield(L, -2, "field3");

        lua_settable(L, -3);

    lua_pushnumber(L, 2);
        lua_createtable(L, 0, 3);

        lua_pushnumber(L, 10);
        lua_setfield(L, -2, "field1");

        lua_pushnumber(L, 20);
        lua_setfield(L, -2, "field2");

        lua_pushnumber(L, 30);
        lua_setfield(L, -2, "field3");

        lua_settable(L, -3);
}

int InternalHello(lua_State* L) {    
    int n = lua_gettop(L);
    std::cout<<"number of arguments: "<<n<<std::endl;
    std::string s = mylua_tolstring(L,1);
    std::cout<<s<<std::endl;
    std::cout<<"Hello World!"<<std::endl;
    //arguments
    if(!lua_istable(L, 2)){
        std::cout<<"para 2 is not table"<<std::endl;
    }else{
        lua_pushnil(L);
        while(lua_next(L,2)){
            printf("%s - %s\n",
              lua_typename(L, lua_type(L, -2)),
              lua_typename(L, lua_type(L, -1)));
              int key = lua_tointeger(L,-2);
              std::string value = mylua_tolstring(L,-1);
              std::cout<<"key: "<<key<<":"<<"value: "<<value<<std::endl;
              lua_pop(L,1); 
        }
    }

    if(!lua_istable(L,3)){
        std::cout<<"para 3 is not table"<<std::endl;
    }else{
        lua_pushnil(L);
        while(lua_next(L,3)){
              std::string key = mylua_tolstring(L,-2);
              std::string value = mylua_tolstring(L,-1);
              std::cout<<"key: "<<key<<":"<<"value: "<<value<<std::endl;
              lua_pop(L,1); 
        }
    }

    if(!lua_istable(L,4)){
        std::cout<<"para 4 is not table"<<std::endl;
    }else{
        lua_pushnil(L);
        while(lua_next(L,4)){
            std::string key = mylua_tolstring(L,-2);
            lua_pushnil(L);
            while(lua_next(L,-2)){
              std::string ikey = mylua_tolstring(L,-2);
              std::string ivalue = mylua_tolstring(L,-1);
              std::cout<<"ikey: "<<ikey<<"  ivalue: "<<ivalue<<std::endl;
              lua_pop(L,1);
           }
           lua_pop(L,1);
        }
    }
    //return values
    //r1
    mylua_pushlstring(L,"ACK");
    //r2
    lua_pushinteger(L,1);
    //r3
    mylua_pushtable(L);
    //r4
    mylua_pushMultiTable(L);
    //r5
    lua_pushnil(L);
    //r6
    lua_pushboolean(L,false);
    //r7
    lua_pushnumber(L,1.24);  

    return 7;
}

int luaopen_firstLib(lua_State *L){
    static const luaL_reg Map[]={
        {"look",InternalHello},
        {NULL,NULL}
    };
    luaL_register(L,"first",Map);
    return 1;
}

```




+ 配套的lua脚本look.lua

```
package.cpath = "./?.so"
require "firstLib"
function printTable(a)
    for k,v in pairs(a) do
        print(k..":"..v)
    end
end

function printMultiTable(a)
    for k,v in pairs(a) do
        for ik,iv in pairs(v) do
            print(ik..":"..iv)
        end
    end
end
para2={"1","SHAOYIWEN","CS"}
para3={["k1"]="v1",["k2"]="v2",["k3"]="v3"}
para4={["k1"]={["ik1"]="v1",["ik2"]="v2"},["k2"]={["ik1"]="v11",["ik2"]="v22"}}

a,b,c,d=first.look("para1",para2,para3,para4)
print(a)
print(b)
printTable(c)
printMultiTable(d)
```





+ 书上给出的栈处理的测试代码

```
//g++ -fPIC -shared -o stacklook.so stacklook.cpp -llua5.1
#include<lua5.1/lua.hpp>
#include<lua5.1/lualib.h>
#include<lua5.1/lauxlib.h>
#include<stdio.h>
#define STACKOP(Code) (Code), LclStackPrint(L, #Code)

static void LclStackPrint(lua_State *L, const char * Str){
    int J, Top;
    printf("%-26s [", Str);
    Top = lua_gettop(L);
    for (J = 1; J <= Top; J++) {
        if (lua_isnil(L, J)) printf("-");
    } 
    printf("]\n");
}

static int LclStackLook(lua_State *L){
// three integers <- stack.look(zero or more integers)
// LclStackLook
    int J, Top;
    for (J = 1, Top = lua_gettop(L); J <= Top; J++)
        luaL_checkinteger(L, J);
        LclStackPrint(L, "Initial stack");
        STACKOP(lua_settop(L, 3));
        STACKOP(lua_settop(L, 5));
        STACKOP(lua_pushinteger(L, 5));
        STACKOP(lua_pushinteger(L, 4));
        STACKOP(lua_replace(L, -4));
        STACKOP(lua_replace(L, 5));
        STACKOP(lua_remove(L, 3));
        STACKOP(lua_pushinteger(L, 3));
        STACKOP(lua_insert(L, -3));
        STACKOP(lua_pushvalue(L, 2));
        STACKOP(lua_pop(L, 1));
        return 3;
} // LclStackLook


extern "C" int luaopen_stacklook(lua_State *L);

int luaopen_stacklook(lua_State *L){
    printf("luaopen_stacklook\n");
    static const luaL_reg Map[] = {
        //User call look instead of LclStackLook 
        {"look", LclStackLook},
        {NULL, NULL}
    };
    //the name of the module is stack instead of stacklook
    luaL_register(L, "stack", Map);

    return 1;
} // luaopen_stacklook

```



#### 相关文献参考
[[1] Beginning Lua Programming, Chapter11, 13]()
[[2] https://www.lua.org/pil/8.2.html](https://www.lua.org/pil/8.2.html)
[[3] 官方文档 https://www.lua.org/manual/5.1/](https://www.lua.org/manual/5.1/)
[[4] http://stackoverflow.com/questions/20147027/creating-a-simple-table-with-lua-tables-c-api](http://stackoverflow.com/questions/20147027/creating-a-simple-table-with-lua-tables-c-api)


