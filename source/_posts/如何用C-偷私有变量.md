---
title: 如何用C++偷私有变量
date: 2017-01-16 09:34:04
tags: just for fun
categories: C++
---


最近在开源代码中发现了一种不修改代码的情况下, 访问库中的类的私有成员变量的方法.  我们知道, 一个类的成员变量设置成private, 外部函数一般通过友元才能访问. 但是库已经写好了, 在不修改库的代码, 为其添加友元的情况下, 也可以使用一些特殊技巧访问类的私有成员.
为了介绍这个方法, 首先介绍一些C++中的特性, 如下.

<!--more-->

#### 指向成员的指针(pointer to member variable)
C++中可以定义**指向类成员变量的指针**类型. 这个成员变量可以不是static的. 

[代码来自此链接: stackoverflow/670734](http://stackoverflow.com/questions/670734/c-pointer-to-class-data-member)
```
#include <iostream>
using namespace std;
class Car {
    public:
    int speed;
};

int main() {
    //定义一个指向成员speed的指针, 用成员的地址初始化.
    int Car::*pSpeed = &Car::speed;

    Car c1;
    c1.speed = 1;       // direct access
    cout << "speed is " << c1.speed << endl;
    
    //已经有一个类的时候, 可以通过这个指针来访问类的成员.对于任意不同的类都可
    //以这么干.
    c1.*pSpeed = 2;     // access via pointer to member
    cout << "speed is " << c1.speed << endl;
    return 0;
}
```

从上面的带注释的例子可以看出, 这里的指针和常见的表示具体地址的指针是不一样的. 这样, 我们要访问一个类的成员变量, 除了通过"."访问, 还可以定义指针来访问.

#### 模板显式实例化(template Explicit instantiation)

我们知道, 对于类模板来说, 我们提供模板参数可以实例化一个模板类. 除了这种方法以外, 模板还可以使用[显式实例化](http://en.cppreference.com/w/cpp/language/class_template#Explicit_instantiation), 在显式实例化的时候, 会忽略参数的private属性. 

所以到此, 访问的方法就比较清晰了. 我们可以定义一个指针来指向类的私有成员, 但是由于成员是私有的, 直接赋值不会成功, 所以我们可以利用模板参数的方式完成赋值, 通过显式实例化来忽略private修饰符. 



#### 一个访问私有成员的例子

介绍完了基础知识, 接下来看一个例子. 我们在例子中定义了一个类FortKnox, 里面有一个private成员 value. 这个类是别人写的, 设置private为了让别人不能直接访问, 并且编译到了动态库里面. 但是利用上面介绍的方法, 我们可以偷偷使用类里面的private变量.



[代码改编自stackoverflow/15110526](http://stackoverflow.com/questions/15110526/allowing-access-to-private-members)
```
#include<iostream>
using namespace std;

typedef int value_type;
//定义了一个类,里面有一个private成员,我们不希望别人直接访问
struct FortKnox {
    FortKnox() : value(0) {}
private:
    value_type value;
};

//这是一个指向类的成员变量的指针类型
typedef value_type FortKnox::* stolen_mem_ptr;

//模板定义一个友元函数,返回指向类的成员变量的指针.
template<stolen_mem_ptr MemPtr>
struct Robber {
    friend stolen_mem_ptr steal() {
        return MemPtr;
    }
};
//模板显式初始化, 可以忽略private修饰符, 这样我们的友元函数就可以
//获得指向成员的指针,并且忽略了private
template struct Robber<&FortKnox::value>;
stolen_mem_ptr steal();

int main() {
    FortKnox f;
    //返回指向成员的指针,忽略了private修饰符
    auto accessor = steal();
    //访问私有成员
    cout<<f.*accessor<<endl;
    f.*accessor=1;
    cout<<f.*accessor<<endl;
    return 0;
}
```

#### 总结
这个特性平时应该比较少用到, 既然碰到了, 就记录一下. 




#### 相关文献

[[1] http://bloglitb.blogspot.de/2011/12/access-to-private-members-safer.html](http://bloglitb.blogspot.de/2011/12/access-to-private-members-safer.html)

[[2] http://stackoverflow.com/questions/670734/c-pointer-to-class-data-member](http://stackoverflow.com/questions/670734/c-pointer-to-class-data-member)

[[3] http://stackoverflow.com/questions/15110526/allowing-access-to-private-members](http://stackoverflow.com/questions/15110526/allowing-access-to-private-members)

