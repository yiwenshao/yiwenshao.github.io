---
title: python的yield使用初探
date: 2016-11-26 15:44:48
tags: [python,yield,coroutines]
categories: helloworld
---


最近在开源代码中遇到**yield**关键字, 这里对最近学习的用法做个简单记录. 本文将基于linux 的 cat命令的实现进行说明.

<!--more-->
### 实现一个cat类

linux中的**cat**命令可以接收多个文件名参数, 然后输出文本文件的内容. 我们希望实现一个**cat**类, 然后通过以下的代码调用完成cat的功能.

```c
import sys
if __name__ == '__main__':
    if sys.argv[1:]:
        for line in cat(sys.argv[1:]):
            print(line)
```

要让代码支持for xx in xx的语法, 需要我们的cat(sys.argv[1:])是一个可迭代的类型. 在python中, 这需要实现两个函数**\_\_iter\_\_**与 **next** (在python3中是**\_\_next\_\_**). 其内部基本逻辑是: 在for循环的每次迭代中, 都会调用next函数, 并返回一个值. 所以, 在类初始化的时候, 需要获得一个参数列表, 也就是需要用cat来处理的文件名. 在编写next函数的时候, 其内部逻辑是, 先打开文件, 然后返回一行数据, 保留文件当前读取位置. 如果当前文件没有内容了, 就关闭文件, 打开下一个文件, 继续处理. 如果所有文件都显示完毕, 就通过产生一个StopIteration异常结束迭代, 其代码如下:

```c
class cat:
    def __init__(self, files):
        self.files = files
        self.cur_file = None
    def __iter__(self):
        return self
    def next(self):
        while True:
            if self.cur_file:
                line = self.cur_file.readline()
                if line:
                    return line.rstrip()
                self.cur_file.close()
            if self.files:
                self.cur_file = open(self.files[0])
                self.files = self.files[1:]
            else:
                raise StopIteration()
```

这样, 我们实现了一个cat类, 满足了我们之前的需要. 在这里, 我们需要多次调用next函数来返回数据, 从第一个文件到最后一个文件, 从每个文件的第一行到最后一行, 也就是说, 这个函数不同的调用有不同的状态. 我们在这里使用了两个变量cur\_file和files来保存状态, 并通过类来封装.

对于上面的实现, 我们使用了readline来读取一行, 然后返回. 这样每次调用next函数, 内部就调用一次readline读取下一行.由于对文件使用readline函数读取能够保存当前的读取位置, 我们总能读取到正确的行. 

现在考虑如果这个返回过程放在一个for循环中会怎么样? 能否在一个for循环中每次调用返回一行, 下次调用函数的时候, 继续返回下一行呢? yield支持这种行为, 也即对函数的调用, 如果返回了, 下一次调用不是从头执行, 而是从上次中断的地方执行, 可以看成带状态的函数, 具体如下:

### yield关键字介绍

#### 一段小程序
首先来看一段用到yield关键字的代码:

```c
def tg():
    print("hehe")
    yield 1
    yield 2
    yield 3

f=tg()
print type(f)
print f.next()
print f.next()
print f.next()
```

执行上面的代码, 可以获得以下的结果:

```
<type 'generator'>
hehe
1
2
3
```

yield 的作用和return类似, 但是含有yield的函数其返回的不是yield关键字后面的类型,而是一个generator类型, 那么generator是什么呢?

generator是一个可迭代的类型, 支持**for item in xx**的使用方式. 也可以直接像上面的例子那样, 调用next函数获取下一个元素. 在循环的每一次, 都会执行到一个yield, 下次则跳过上次执行过的yield, 直接执行下一个yield的代码, 并给出返回结果.

#### 基于yield的cat命令

有了上面的分析, 下面给出基于yield实现cat命令的完整代码.可以看到, 由于能够从上次执行结束的地方继续执行, 我们的代码变得更加符合直观的逻辑:

```
import sys
def cat(files):
    for fn in files:
            f = open(fn)
            for line in f:
                yield line.rstrip()

if __name__ == '__main__':
    if sys.argv[1:]:
        for line in cat(sys.argv[1:]):
           print(line)
```


### 相关文献

[[1] https://yongweiwu.wordpress.com/2016/08/16/python-yield-and-cplusplus-coroutines/](https://yongweiwu.wordpress.com/2016/08/16/python-yield-and-cplusplus-coroutines/)

[[2] https://docs.python.org/2/tutorial/classes.html#generators](https://docs.python.org/2/tutorial/classes.html#generators)

[[3] http://stackoverflow.com/questions/231767/what-does-the-yield-keyword-do](http://stackoverflow.com/questions/231767/what-does-the-yield-keyword-do)

[[4] http://effbot.org/zone/python-for-statement.htm](http://effbot.org/zone/python-for-statement.htm)

[[5] http://stackoverflow.com/questions/19151/build-a-basic-python-iterator](http://stackoverflow.com/questions/19151/build-a-basic-python-iterator)
