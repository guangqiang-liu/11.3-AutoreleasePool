# 11.1-autoreleasePool实现原理下

我们在分析自动释放池底层源码前，我们先来创建一个新工程，查看`main`函数中系统创建的自动释放池最终转换为底层c++代码的情况

`main`函数

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
    }
    return 0;
}
```

我们执行命令`xcrun  -sdk  iphoneos  clang  -arch  arm64  -rewrite-objc main.m`将`main.m`文件转换为底层c++文件，核心代码如下：

```
int main(int argc, const char * argv[]) {
    /* @autoreleasepool */ {
        __AtAutoreleasePool __autoreleasepool;
    }
    return 0;
}
```

从上面的转换我们可以看出，将创建自动释放池的代码`@autoreleasepool{}`转换为了底层代码` __AtAutoreleasePool __autoreleasepool;`

`__AtAutoreleasePool __autoreleasepool;`声明了一个`__AtAutoreleasePool`类型的变量，我们再来看看`__AtAutoreleasePool`的类型，我们通过在`main.cpp`文件中搜索，发现`__AtAutoreleasePool`为一个结构体对象，源码如下：

```
extern "C" __declspec(dllimport) void * objc_autoreleasePoolPush(void);
extern "C" __declspec(dllimport) void objc_autoreleasePoolPop(void *);

struct __AtAutoreleasePool {
    // 构造函数，在初始化创建结构体的时候调用
  __AtAutoreleasePool() {
      atautoreleasepoolobj = objc_autoreleasePoolPush();
  }
    
    // 析构函数，在结构体对象销毁的时候调用
  ~__AtAutoreleasePool() {
      objc_autoreleasePoolPop(atautoreleasepoolobj);
  }
    
  void * atautoreleasepoolobj;
};
```

我们发现在`__AtAutoreleasePool`结构体的构造函数中调用了`objc_autoreleasePoolPush()`函数，在析构函数中调用了`objc_autoreleasePoolPop()`函数

我们知道创建自动释放池除了使用`@autoreleasepool{}`这种方式，我们还可以使用下面的面向对象的语法：

```
	// 创建自动释放池
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSObject *obj = [[NSObject alloc] init];
    
    // 将对象添加到自动释放池
    [obj autorelease];
    
    // 销毁自动释放池
    [pool drain];
```

这两种创建自动释放池方式的等价操作如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/1455700240202950.png)

通过使用`NSAutoreleasePool`的方式创建的自动释放池和使用`@autoreleasepool{}`这种方式最终生成的结构体`__AtAutoreleasePool`进行对比，我们可以知道

```
@autoreleasepool { // 大括号作用域前调用：objc_autoreleasePoolPush()

    NSObject *obj = [[NSObject alloc] init];
    [obj autorelease];
    
} // 大括号作用域结束前调用：objc_autoreleasePoolPop()
```

`@autoreleasepool {}`方式创建的自动释放池，在作用域大括号的开始前会调用`objc_autoreleasePoolPush()`函数，在作用域大括号的结束前会调用`objc_autoreleasePoolPop()`函数

然后类比使用`NSAutoreleasePool`创建自动释放池，在执行`NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]`时会调用`objc_autoreleasePoolPush()`函数，在执行`[pool drain]`时会调用`objc_autoreleasePoolPop()`函数，等价于下面的代码

```
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    /* 等同于objc_autoreleasePoolPush() */
    
    NSObject *obj = [[NSObject alloc] init];
    
    [obj autorelease];
    /* 等同于objc_autorelease(obj) */
    
    [pool drain];
    /* 等同于objc_autoreleasePoolPop(pool) */
```

上面我们一直提到`objc_autoreleasePoolPush`和`objc_autoreleasePoolPop`函数，接下来我们再来看看这两个函数的具体作用，源码查看路径：`objc4 -> NSObject.mm -> void *
objc_autoreleasePoolPush(void)`

源码对这两个函数的定义如下：

```
void * objc_autoreleasePoolPush(void)
{
    return AutoreleasePoolPage::push();
}

void objc_autoreleasePoolPop(void *ctxt)
{
    AutoreleasePoolPage::pop(ctxt);
}
```

通过上面的源码我们看一看到Push和Pop函数最终都是通过`AutoreleasePoolPage`来调用的，接下来我们再来看看`AutoreleasePoolPage`的源码，源码查看路径：`objc4 -> NSObject.mm -> AutoreleasePoolPage`

通过源码查看我们发现`AutoreleasePoolPage`是一个类，`AutoreleasePoolPage`类的核心源码如下：

```
/***********************************************************************
   Autorelease pool implementation

   A thread's autorelease pool is a stack of pointers. 
   Each pointer is either an object to release, or POOL_BOUNDARY which is 
     an autorelease pool boundary.
   A pool token is a pointer to the POOL_BOUNDARY for that pool. When 
     the pool is popped, every object hotter than the sentinel is released.
   The stack is divided into a doubly-linked list of pages. Pages are added 
     and deleted as necessary. 
   Thread-local storage points to the hot page, where newly autoreleased 
     objects are stored. 
**********************************************************************/
class AutoreleasePoolPage 
{
	 // ************** AutoreleasePoolPage类的七个成员变量 **************
	 
	 magic_t const magic;
    
    // 这个指针是指Page可以存放下一个autorelease对象的地址值
    id *next;
    
    // 当前所在的线程
    pthread_t const thread;
    
    // 指向上一个page对象
    AutoreleasePoolPage * const parent;
    
    // 指向下一个page对象
    AutoreleasePoolPage *child;
    
    // 自动释放池Page的深度
    uint32_t const depth;
    uint32_t hiwat;
        
    // ************** AutoreleasePoolPage类的核心函数 **************
    
    // autorelease：对象调用autorelease方法，将对象添加到自动释放池中
public:
    static inline id autorelease(id obj)
    {
        assert(obj);
        assert(!obj->isTaggedPointer());
        
        // 通过autoreleaseFast函数，找到这个对象的内存地址
        id *dest __unused = autoreleaseFast(obj);
        
        assert(!dest  ||  dest == EMPTY_POOL_PLACEHOLDER  ||  *dest == obj);
        
        return obj;
    }
    
    // AutoreleasePoolPage类中的 push 函数
    static inline void *push() 
    {
        id *dest;
        if (DebugPoolAllocation) {
            // Each autorelease pool starts on a new pool page.
            
            // 当没有Page时，创建一个Page，将POOL_BOUNDARY放入到page中入栈，然后返回这个位置的内存地址值
            dest = autoreleaseNewPage(POOL_BOUNDARY);
        } else {
            // 已经有Page
            dest = autoreleaseFast(POOL_BOUNDARY);
        }
        assert(dest == EMPTY_POOL_PLACEHOLDER || *dest == POOL_BOUNDARY);
        
        // 返回值，也就是Page开始存放对象时POOL_BOUNDARY入栈时对应Page中的内存地址
        return dest;
    }
    
    
    // AutoreleasePoolPage类中的Pop函数，这里的token就是POOL_BOUNDARY
    // pop函数会从栈底开始一直往上释放对象，直到释放到POOL_BOUNDARY的位置截止
    static inline void pop(void *token) 
    {
        
        AutoreleasePoolPage *page;
        id *stop;

        if (token == (void*)EMPTY_POOL_PLACEHOLDER) {
            // Popping the top-level placeholder pool.
            
            // 判断是否为当前的自动释放池
            if (hotPage()) {
                // Pool was used. Pop its contents normally.
                // Pool pages remain allocated for re-use as usual.
                pop(coldPage()->begin());
            } else {
                // Pool was never used. Clear the placeholder.
                setHotPage(nil);
            }
            return;
        }

        page = pageForPointer(token);
        
        // 将token(POOL_BOUNDARY)赋值给stop指针
        stop = (id *)token;
        
        if (*stop != POOL_BOUNDARY) {
            if (stop == page->begin()  &&  !page->parent) {
                // Start of coldest page may correctly not be POOL_BOUNDARY:
                // 1. top-level pool is popped, leaving the cold page in place
                // 2. an object is autoreleased with no pool
            } else {
                // Error. For bincompat purposes this is not 
                // fatal in executables built with old SDKs.
                return badPop(token);
            }
        }

        if (PrintPoolHiwat) printHiwat();

        // 这里我们可以看到，自动释放池释放对象，是通过一个终止释放的标记来从后往前释放池中的对象
        page->releaseUntil(stop);

        
        // memory: delete empty children
        if (DebugPoolAllocation  &&  page->empty()) {
            // special case: delete everything during page-per-pool debugging
            AutoreleasePoolPage *parent = page->parent;
            page->kill();
            setHotPage(parent);
        } else if (DebugMissingPools  &&  page->empty()  &&  !page->parent) {
            // special case: delete everything for pop(top) 
            // when debugging missing autorelease pools
            page->kill();
            setHotPage(nil);
        } 
        else if (page->child) {
            // hysteresis: keep one empty child if page is more than half full
            if (page->lessThanHalfFull()) {
                page->child->kill();
            }
            else if (page->child->child) {
                page->child->child->kill();
            }
        }
    }
}
```

从`AutoreleasePoolPage`类的核心源码可以知道，当执行`objc_autoreleasePoolPush()`函数时，就是调用`AutoreleasePoolPage`类的`push`函数，当执行`objc_autoreleasePoolPop()`函数就是调用`AutoreleasePoolPage`类的`pop`函数，当调用对象的`autorelease`函数时就是调用`AutoreleasePoolPage`类的`autorelease`函数

我们从如下`Autorelease pool`的底层源码注释可知：

```
	Autorelease pool implementation

   A thread's autorelease pool is a stack of pointers. 
   Each pointer is either an object to release, or POOL_BOUNDARY which is 
     an autorelease pool boundary.
   A pool token is a pointer to the POOL_BOUNDARY for that pool. When 
     the pool is popped, every object hotter than the sentinel is released.
   The stack is divided into a doubly-linked list of pages. Pages are added 
     and deleted as necessary. 
   Thread-local storage points to the hot page, where newly autoreleased 
     objects are stored. 
```

自动释放池是由很多个`AutoreleasePoolPage`组成的一个双向链表的结构，并且每一个`AutoreleasePoolPage`中存放自动释放的对象都是以栈的形式存储的，如下图所示：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200219-175246@2x.png)

这里有一个比较关键的指针`POOL_BOUNDARY`

例如：当我们创建一个自动释放池，这时就有一个`POOL_BOUNDARY`指针入栈存储在`AutoreleasePoolPage`表中，我们可以通过下面的`push`函数验证：

```
static inline void *push() 
{
    id *dest;
    if (DebugPoolAllocation) {
        // Each autorelease pool starts on a new pool page.
        
        // 当没有Page时，创建一个Page，将POOL_BOUNDARY放入到page中入栈，然后返回这个位置的内存地址
        dest = autoreleaseNewPage(POOL_BOUNDARY);
    } else {
        // 已经有Page
        dest = autoreleaseFast(POOL_BOUNDARY);
    }
    assert(dest == EMPTY_POOL_PLACEHOLDER || *dest == POOL_BOUNDARY);
    
    // 返回值，也就是Page开始存放对象时POOL_BOUNDARY入栈时对应Page中的内存地址
    return dest;
}
```

然后我们创建10个对象调用`autorelease`方法逐一添加到自动释放池中，`autorelease`函数：

```
public:
    static inline id autorelease(id obj)
    {
        assert(obj);
        assert(!obj->isTaggedPointer());
        
        // 通过调用autoreleaseFast函数，将obj对象添加至池中
        id *dest __unused = autoreleaseFast(obj);
        
        assert(!dest  ||  dest == EMPTY_POOL_PLACEHOLDER  ||  *dest == obj);
        
        return obj;
    }
```

`autoreleaseFast`函数：

```
static inline id *autoreleaseFast(id obj)
    {
        AutoreleasePoolPage *page = hotPage();
        if (page && !page->full()) {
            
            // 将obj对象添加到page中
            return page->add(obj);
        } else if (page) {
            return autoreleaseFullPage(obj, page);
        } else {
            return autoreleaseNoPage(obj);
        }
    }
```

在`autoreleaseFast`函数中，我们看到，不管是当前page没有满，还是当前page满了或者是还没有page，最终都调用了`page->add(obj)`语句将对象添加至池中

当需要销毁这10个对象时，这时需要调用`pop`函数，源码如下：

```
static inline void pop(void *token) 
    {
        
        AutoreleasePoolPage *page;
        id *stop;

        if (token == (void*)EMPTY_POOL_PLACEHOLDER) {
            // Popping the top-level placeholder pool.
            
            // 判断是否为当前的自动释放池
            if (hotPage()) {
                // Pool was used. Pop its contents normally.
                // Pool pages remain allocated for re-use as usual.
                pop(coldPage()->begin());
            } else {
                // Pool was never used. Clear the placeholder.
                setHotPage(nil);
            }
            return;
        }

        page = pageForPointer(token);
        
        // 将token(POOL_BOUNDARY)赋值给stop指针
        stop = (id *)token;
        
        if (*stop != POOL_BOUNDARY) {
            if (stop == page->begin()  &&  !page->parent) {
                // Start of coldest page may correctly not be POOL_BOUNDARY:
                // 1. top-level pool is popped, leaving the cold page in place
                // 2. an object is autoreleased with no pool
            } else {
                // Error. For bincompat purposes this is not 
                // fatal in executables built with old SDKs.
                return badPop(token);
            }
        }

        if (PrintPoolHiwat) printHiwat();

        // 这里我们可以看到，自动释放池释放对象，是通过一个终止释放的标记来从后往前释放池中的对象
        page->releaseUntil(stop);

        
        // memory: delete empty children
        if (DebugPoolAllocation  &&  page->empty()) {
            // special case: delete everything during page-per-pool debugging
            AutoreleasePoolPage *parent = page->parent;
            page->kill();
            setHotPage(parent);
        } else if (DebugMissingPools  &&  page->empty()  &&  !page->parent) {
            // special case: delete everything for pop(top) 
            // when debugging missing autorelease pools
            page->kill();
            setHotPage(nil);
        } 
        else if (page->child) {
            // hysteresis: keep one empty child if page is more than half full
            if (page->lessThanHalfFull()) {
                page->child->kill();
            }
            else if (page->child->child) {
                page->child->child->kill();
            }
        }
    }
```

从上面的源码我们看到，调用`pop`函数有传一个参数`token`，这个`token`是一个指针，正是开始创建自动释放池时函数的返回值，这个值就是`POOL_BOUNDARY`，我们从编译出的c++文件源码可知

```
struct __AtAutoreleasePool {
    // 构造函数，在初始化创建结构体的时候调用
  __AtAutoreleasePool() {
  		// 创建自动释放池时调用objc_autoreleasePoolPush函数，并返回atautoreleasepoolobj，这个就是入栈的`POOL_BOUNDARY`的地址
      atautoreleasepoolobj = objc_autoreleasePoolPush();
  }
    
    // 析构函数，在结构体对象销毁的时候调用
  ~__AtAutoreleasePool() {
  		// 销毁自动释放池时调用`objc_autoreleasePoolPop`函数，将`POOL_BOUNDARY`地址传入
      objc_autoreleasePoolPop(atautoreleasepoolobj);
  }
   
   // atautoreleasepoolobj为指针类型
  void * atautoreleasepoolobj;
};
```

我们在来看`pop`函数，当把`token`地址赋值给`stop`指针后，执行了`page->releaseUntil(stop)`语句，我们来看看`releaseUntil`函数，源码如下：

```
// 自动释放池释放对象，从后往前开始释放，直到遇到stop地址停止释放
void releaseUntil(id *stop) 
{
    // Not recursive: we don't want to blow out the stack 
    // if a thread accumulates a stupendous amount of garbage
    
    // 开始循环释放对象
    while (this->next != stop) {
        // Restart from hotPage() every time, in case -release 
        // autoreleased more objects
        
        // 获取到当前正在使用的Page，也就是热Page
        AutoreleasePoolPage *page = hotPage();

        // fixme I think this `while` can be `if`, but I can't prove it
        while (page->empty()) {
            page = page->parent;
            setHotPage(page);
        }

        page->unprotect();
        
        // 取出`next`指针指向的对象地址
        id obj = *--page->next;
        
        memset((void*)page->next, SCRIBBLE, sizeof(*page->next));
        page->protect();

        // 一直循环遍历释放对象，知道遇到POOL_BOUNDARY地址
        if (obj != POOL_BOUNDARY) {
            // 这里就是释放对象的最终位置
            objc_release(obj);
        }
    }

    setHotPage(this);

#if DEBUG
    // we expect any children to be completely empty
    for (AutoreleasePoolPage *page = child; page; page = page->child) {
        assert(page->empty());
    }
#endif
}
```

在`releaseUntil()`函数中，我们看到了核心代码：

```
	// 开始循环释放对象
	while (this->next != stop) {
	    // 一直循环遍历释放对象，知道遇到POOL_BOUNDARY地址
	    if (obj != POOL_BOUNDARY) {
	        // 这里就是释放对象的最终位置
	        objc_release(obj);
	    }
	}
```

在while循环中判断，如果地址不等于POOL_BOUNDARY，就执行`objc_release()`释放对象，直到地址为POOL_BOUNDARY停止释放，到这我们应该就明白POOL_BOUNDARY的作用了

上面`Autorelease pool`源码注释我们知道，自动释放池是由很多个`AutoreleasePoolPage`组成的双向链表结构，那每一个`AutoreleasePoolPage`又分配了多大的存储空间尼

我们通过前面的源码`static size_t const COUNT = SIZE / sizeof(id);`中的`SIZE`的定义

```
#define I386_PGBYTES            4096            /* bytes per 80386 page */
```

从宏定义中可以看出每页`page`有4096字节的大小，由于`AutoreleasePoolPage`类中声明了7个成员变量，每个成员变量占8字节，所以说每页`page`还有4040(4096-56)个字节大小用来存放对象，如果这一页数据存满了，那么就接着存放在下一页`page`中，以此类推

在上面的源码分析过程我们也有看到`hotPage`和`coldPage`函数，这两个很好理解，当前正在使用的`page`就是`hotPage`，前面已经存放满对象的`page`就是`coldPage`，这个后面代码打印当前自动释放池的情况，看输出结果就一目了然了

上面是通过`Autorelease Pool`底层源码进行的分析，下面我们再来通过测试代码来看看自动释放池的使用情况，这里由于`ARC`和`MRC`使用`Autorelease Pool`的情况有点不同，这里我们就分开来看测试效果

**我们先来看看MRC的测试情况**

我们先新建一个工程，然后将`Automatic Reference Counting`改为NO，然后创建一个`Person`类，一个`Dog`类，测试代码如下：

`Person`类

```
@interface Person : NSObject
{
    Dog *_dog;
}

- (void)setDog:(Dog *)dog;

- (Dog *)dog;
@end


@implementation Person

- (void)setDog:(Dog *)dog {
    if (dog != _dog) {
        [_dog release];
        dog = [dog retain];
        _dog = dog;
    }
}

- (Dog *)dog {
    return _dog;
}

- (void)dealloc {
    
    NSLog(@"%s", __func__);
    self.dog = nil;
    
    [super dealloc];
}
@end
```

`Dog`类

```
@interface Dog : NSObject

@end


@implementation Dog

- (void)dealloc {
    [super dealloc];
    
    NSLog(@"%s", __func__);
}
@end
```

`main`函数

```
// _objc_autoreleasePoolPrint()函数可以打印出当前自动释放池的使用情况，在ARC和MRC下都可用
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        // 注意：当前是MRC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        _objc_autoreleasePoolPrint();
    }
    return 0;
}
```

在`main`函数中，我们先来看看最简单的情况，就是没有任何对象添加到自动释放池时，我们使用`_objc_autoreleasePoolPrint()`函数来打印池中的情况，自动释放池打印如下：

```
objc[72048]: ##############
objc[72048]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72048]: 1 releases pending.
objc[72048]: [0x103802000]  ................  PAGE  (hot) (cold)
objc[72048]: [0x103802038]  ################  POOL 0x103802038
objc[72048]: ##############
```

从上面的打印我们可以看出，`1 releases pending`，表示当前池中就一个对象，这个对象就是`POOL 0x103802038`，也就是上面所讲的`POOL_BOUNDARY`指针

接下来我们修改下`main`函数，我们创建对象调用`autorelease`添加到池中，然后创建对象不调用`autorelease`，对比看下差别，测试代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        // 注意：当前是MRC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"--------------------------------");
        
        Person *p1 = [[Person alloc] init];
        [p1 autorelease];
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"--------------------------------");
        
        Dog *d1 = [[Dog alloc] init];
        
        _objc_autoreleasePoolPrint();
    }
    return 0;
}
```

自动释放池打印如下：

```
objc[72119]: ##############
objc[72119]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72119]: 1 releases pending.
objc[72119]: [0x100801000]  ................  PAGE  (hot) (cold)
objc[72119]: [0x100801038]  ################  POOL 0x100801038
objc[72119]: ##############
--------------------------------
objc[72119]: ##############
objc[72119]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72119]: 2 releases pending.
objc[72119]: [0x100801000]  ................  PAGE  (hot) (cold)
objc[72119]: [0x100801038]  ################  POOL 0x100801038
objc[72119]: [0x100801040]       0x10060f850  Person
objc[72119]: ##############
--------------------------------
objc[72119]: ##############
objc[72119]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72119]: 2 releases pending.
objc[72119]: [0x100801000]  ................  PAGE  (hot) (cold)
objc[72119]: [0x100801038]  ################  POOL 0x100801038
objc[72119]: [0x100801040]       0x10060f850  Person
objc[72119]: ##############
```

从上面的打印，我们可以看到，当我们不添加任何对象到池中时，池中就一个对象`POOL_BOUNDARY`，当我们创建一个`Person`对象添加到池中后，可以看到池中有了2个对象，除了最开始的`POOL_BOUNDARY`，还新增了`0x10060f850  Person`，然而当我们创建一个`Dog`对象，但是没有调用`autorelease`，我们发现`Dog`对象的地址没有添加到池中。从这个对比我们知道了，要想让对象添加到自动释放池，对象就需要调用`autorelease`方法

接下来我们来看下自动释放池嵌套使用的情况，测试代码如下：

```
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        // 注意：当前是MRC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"--------------------------------");
        
        Person *p1 = [[Person alloc] init];
        [p1 autorelease];
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"--------------------------------");
        
        @autoreleasepool {
            Person *p2 = [[Person alloc] init];
            [p2 autorelease];
            
            Dog *d2 = [[Dog alloc] init];
            [d2 autorelease];
            
            _objc_autoreleasePoolPrint();
            
            NSLog(@"--------------------------------");
            
            @autoreleasepool {
                Person *p3 = [[Person alloc] init];
                [p3 autorelease];
                
                Cat *cat3 = [[Cat alloc] init];
                [cat3 autorelease];
                
                NSLog(@"--------------------------------");
                
                _objc_autoreleasePoolPrint();
            }
        }
    }
    return 0;
}
```

`_objc_autoreleasePoolPrint()`函数打印如下：

```
objc[72275]: ##############
objc[72275]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72275]: 1 releases pending.
objc[72275]: [0x105800000]  ................  PAGE  (hot) (cold)
objc[72275]: [0x105800038]  ################  POOL 0x105800038
objc[72275]: ##############
--------------------------------
objc[72275]: ##############
objc[72275]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72275]: 2 releases pending.
objc[72275]: [0x105800000]  ................  PAGE  (hot) (cold)
objc[72275]: [0x105800038]  ################  POOL 0x105800038
objc[72275]: [0x105800040]       0x1023057d0  Person
objc[72275]: ##############
--------------------------------
objc[72275]: ##############
objc[72275]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72275]: 5 releases pending.
objc[72275]: [0x105800000]  ................  PAGE  (hot) (cold)
objc[72275]: [0x105800038]  ################  POOL 0x105800038
objc[72275]: [0x105800040]       0x1023057d0  Person
objc[72275]: [0x105800048]  ################  POOL 0x105800048
objc[72275]: [0x105800050]       0x10073af00  Person
objc[72275]: [0x105800058]       0x10073d3b0  Dog
objc[72275]: ##############
--------------------------------
objc[72275]: ##############
objc[72275]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72275]: 8 releases pending.
objc[72275]: [0x105800000]  ................  PAGE  (hot) (cold)
objc[72275]: [0x105800038]  ################  POOL 0x105800038
objc[72275]: [0x105800040]       0x1023057d0  Person
objc[72275]: [0x105800048]  ################  POOL 0x105800048
objc[72275]: [0x105800050]       0x10073af00  Person
objc[72275]: [0x105800058]       0x10073d3b0  Dog
objc[72275]: [0x105800060]  ################  POOL 0x105800060
objc[72275]: [0x105800068]       0x10244f2f0  Person
objc[72275]: [0x105800070]       0x10244ee70  Cat
objc[72275]: ##############
--------------------------------
2020-02-19 10:48:27.081520+0800 aaaaaaa[72275:5367840] -[Cat dealloc]
2020-02-19 10:48:27.081564+0800 aaaaaaa[72275:5367840] -[Person dealloc]
2020-02-19 10:48:27.081606+0800 aaaaaaa[72275:5367840] -[Dog dealloc]
2020-02-19 10:48:27.081641+0800 aaaaaaa[72275:5367840] -[Person dealloc]
2020-02-19 10:48:27.081675+0800 aaaaaaa[72275:5367840] -[Person dealloc]
```

上面我们进行了3层自动释放池的嵌套操作，我们从最后一次执行`_objc_autoreleasePoolPrint()`打印可以看出，每当我们使用`@autoreleasepool {}`创建一个自动释放池，就会有一个`POOL_BOUNDARY`入栈，我们从下面打印可以看出

```
objc[72275]: ##############
objc[72275]: AUTORELEASE POOLS for thread 0x1000aa5c0
objc[72275]: 8 releases pending.
objc[72275]: [0x105800000]  ................  PAGE  (hot) (cold)
objc[72275]: [0x105800038]  ################  POOL 0x105800038
objc[72275]: [0x105800040]       0x1023057d0  Person
objc[72275]: [0x105800048]  ################  POOL 0x105800048
objc[72275]: [0x105800050]       0x10073af00  Person
objc[72275]: [0x105800058]       0x10073d3b0  Dog
objc[72275]: [0x105800060]  ################  POOL 0x105800060
objc[72275]: [0x105800068]       0x10244f2f0  Person
objc[72275]: [0x105800070]       0x10244ee70  Cat
objc[72275]: ##############
```

接下来我们再来看看当嵌套的自动释放池超出了作用域会有什么结果，测试代码如下：

```
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    
    @autoreleasepool { // 第一个自动释放池
        // insert code here...
        
        // 注意：当前是MRC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        Person *p1 = [[Person alloc] init];
        [p1 autorelease];
    
        @autoreleasepool { // 第二个自动释放池
            Person *p2 = [[Person alloc] init];
            [p2 autorelease];
            
            Dog *d2 = [[Dog alloc] init];
            [d2 autorelease];
            
            @autoreleasepool { // 第三个自动释放池
                Person *p3 = [[Person alloc] init];
                [p3 autorelease];
                
                Cat *cat3 = [[Cat alloc] init];
                [cat3 autorelease];
                                
                _objc_autoreleasePoolPrint();
                
                NSLog(@"--------------------------------");
            }
            
            NSLog(@"第三个自动释放池超出了作用域");
            
            _objc_autoreleasePoolPrint();
            
            NSLog(@"--------------------------------");
        }
        
         NSLog(@"第二个自动释放池超出了作用域");
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"--------------------------------");
    }
    
    NSLog(@"第一个自动释放池超出了作用域");
    
    _objc_autoreleasePoolPrint();
    
    NSLog(@"--------------------------------");
    
    return 0;
}
```

终端打印结果如下：

```
objc[72410]: ##############
objc[72410]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72410]: 8 releases pending.
objc[72410]: [0x105803000]  ................  PAGE  (hot) (cold)
objc[72410]: [0x105803038]  ################  POOL 0x105803038
objc[72410]: [0x105803040]       0x1007045c0  Person
objc[72410]: [0x105803048]  ################  POOL 0x105803048
objc[72410]: [0x105803050]       0x100704170  Person
objc[72410]: [0x105803058]       0x100700be0  Dog
objc[72410]: [0x105803060]  ################  POOL 0x105803060
objc[72410]: [0x105803068]       0x100702760  Person
objc[72410]: [0x105803070]       0x100700dc0  Cat
objc[72410]: ##############
--------------------------------
aaaaaaa[72410:5388081] -[Cat dealloc]
aaaaaaa[72410:5388081] -[Person dealloc]
aaaaaaa[72410:5388081] 第三个自动释放池超出了作用域
objc[72410]: ##############
objc[72410]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72410]: 5 releases pending.
objc[72410]: [0x105803000]  ................  PAGE  (hot) (cold)
objc[72410]: [0x105803038]  ################  POOL 0x105803038
objc[72410]: [0x105803040]       0x1007045c0  Person
objc[72410]: [0x105803048]  ################  POOL 0x105803048
objc[72410]: [0x105803050]       0x100704170  Person
objc[72410]: [0x105803058]       0x100700be0  Dog
objc[72410]: ##############
--------------------------------
aaaaaaa[72410:5388081] -[Dog dealloc]
aaaaaaa[72410:5388081] -[Person dealloc]
aaaaaaa[72410:5388081] 第二个自动释放池超出了作用域
objc[72410]: ##############
objc[72410]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72410]: 2 releases pending.
objc[72410]: [0x105803000]  ................  PAGE  (hot) (cold)
objc[72410]: [0x105803038]  ################  POOL 0x105803038
objc[72410]: [0x105803040]       0x1007045c0  Person
objc[72410]: ##############
--------------------------------
aaaaaaa[72410:5388081] -[Person dealloc]
aaaaaaa[72410:5388081] 第一个自动释放池超出了作用域
objc[72410]: ##############
objc[72410]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72410]: 0 releases pending.
objc[72410]: [0x105803000]  ................  PAGE  (hot) (cold)
objc[72410]: ##############
```

我们从上面的打印可以看到，当第三个自动释放池超出了作用域(也就是执行完`@autoreleasepool {}`的结束大括号)后，在第三个自动释放池中创建的`Person`和`Cat`对象就已经销毁了，我们从`_objc_autoreleasePoolPrint()`打印也可以看出，此时池中已经没有了第三个自动释放池的`POOL_BOUNDARY`地址，和`Person`，`Cat`的地址了，也就是说第三个自动释放池也销毁了。当第二个自动释放池超出作用域，原理和第三个自动释放池一样。我们在看下`main`函数中系统创建的第一个自动释放池超出作用域后的情况，从打印`0 releases pending.`可以看出，此时池中已经没有任何对象了，第一个自动释放池超出作用域也销毁了。这也正好验证了上面咱们总结的结论：
> 当自动释放池超出作用域，则这个自动释放池就会销毁，当自动释放池销毁时，便会向池中的每一个对象发送`release`消息来销毁池中的对象。

接下来我们再来看看当添加到自动释放池中的对象引用计数大于1时，当自动释放池销毁时，引用计数大于1的对象是进行引用计数-1还是说直接释放对象，测试代码如下：

```
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    
    @autoreleasepool { // 第一个自动释放池
        // insert code here...
        
        // 注意：当前是MRC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        @autoreleasepool { // 第二个自动释放池
            Person *p1 = [[[Person alloc] init] autorelease];
            Person *p2 = [[[Person alloc] init] autorelease];
            
            Dog *dog = [[[Dog alloc] init] autorelease]; // dog引用计数=1
            
            NSLog(@"%zd", [dog retainCount]); // 1
            
            [p1 setDog:dog]; // dog引用计数=2
            [p2 setDog:dog]; // dog引用计数=3
                    
            NSLog(@"%zd", [dog retainCount]); // 3
            
            _objc_autoreleasePoolPrint();
            
            NSLog(@"-------------------");
        }
        
        NSLog(@"---------第二个自动释放池超出作用域---------");
        
        _objc_autoreleasePoolPrint();
    }
    
    return 0;
}
```

终端打印数据如下：

```
13:44:18.661853+0800 aaaaaaa[72892:5442548] 1
13:44:18.661890+0800 aaaaaaa[72892:5442548] 3
objc[72892]: ##############
objc[72892]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72892]: 5 releases pending.
objc[72892]: [0x100803000]  ................  PAGE  (hot) (cold)
objc[72892]: [0x100803038]  ################  POOL 0x100803038
objc[72892]: [0x100803040]  ################  POOL 0x100803040
objc[72892]: [0x100803048]       0x100622450  Person
objc[72892]: [0x100803050]       0x100620f20  Person
objc[72892]: [0x100803058]       0x100624990  Dog
objc[72892]: ##############
13:44:18.662157+0800 aaaaaaa[72892:5442548] -------------------
13:44:18.662209+0800 aaaaaaa[72892:5442548] -[Person dealloc]
13:44:18.662241+0800 aaaaaaa[72892:5442548] -[Person dealloc]
13:44:18.662280+0800 aaaaaaa[72892:5442548] -[Dog dealloc]
13:44:18.662342+0800 aaaaaaa[72892:5442548] -第二个自动释放池超出作用域-
objc[72892]: ##############
objc[72892]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[72892]: 1 releases pending.
objc[72892]: [0x100803000]  ................  PAGE  (hot) (cold)
objc[72892]: [0x100803038]  ################  POOL 0x100803038
objc[72892]: ##############
```

上面的测试代码，我们创建了一个`Dog`对象，然后分别让`p1`和`p2`对象持有这个`dog`对象，这时`dog`对象的引用计数为3，当第二个自动释放池超出作用域销毁的时，我们通过打印可以看出`dog`对象也销毁了，此时再打印自动释放池的情况，发现池中就剩下第一个自动释放池的`POOL_BOUNDARY`地址了，第二个自动释放池中的所有对象全部都已释放了

上面咱们代码测试自动释放池的情况一直都是使用`@autoreleasepool {}`方式创建的自动释放池，并没有使用`NSAutoreleasePool`类来创建自动释放池，原理都是一样的，这里就不在重复验证了。

**接下来我们再来看看`ARC`环境下的自动释放池的使用情况：**

由于`ARC`环境中我们不能使用`autorelease`和`NSAutoreleasePool`，所以在`ARC`环境中，如果想创建一个自动释放池我们只能选择使用`@autoreleasepool {}`这种方式创建，如果想将对象添加到自动释放池中，我们只能选择使用`__autoreleasing`权限修饰符来修饰这个对象，测试代码如下：

```
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    
    @autoreleasepool { // 第一个自动释放池
        // insert code here...
        
        // 注意：当前是ARC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"---------------------------");
        
        // 没有使用__autoreleasing修饰的对象，不会添加到自动释放池中
        Person *p1 = [[Person alloc] init];
        
        _objc_autoreleasePoolPrint();
        
        // 使用了__autoreleasing的会添加到自动释放池中
        __autoreleasing Person *p2 = [[Person alloc] init];
        
        _objc_autoreleasePoolPrint();
        
    }
    
    NSLog(@"-第一个自动释放池销毁了-");
    
    // 第一个自动释放池超出了作用域，自动释放池销毁，池中的对象也全部释放
    _objc_autoreleasePoolPrint();
    return 0;
}
```

对应的终端打印如下：

```
objc[73081]: ##############
objc[73081]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73081]: 1 releases pending.
objc[73081]: [0x105002000]  ................  PAGE  (hot) (cold)
objc[73081]: [0x105002038]  ################  POOL 0x105002038
objc[73081]: ##############
---------------------------
objc[73081]: ##############
objc[73081]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73081]: 1 releases pending.
objc[73081]: [0x105002000]  ................  PAGE  (hot) (cold)
objc[73081]: [0x105002038]  ################  POOL 0x105002038
objc[73081]: ##############
---------------------------
objc[73081]: ##############
objc[73081]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73081]: 2 releases pending.
objc[73081]: [0x105002000]  ................  PAGE  (hot) (cold)
objc[73081]: [0x105002038]  ################  POOL 0x105002038
objc[73081]: [0x105002040]       0x103a225e0  Person
objc[73081]: ##############
---------------------------
14:18:48.329583+0800 aaaaaaa[73081:5459344] -[Person dealloc]
14:18:48.329638+0800 aaaaaaa[73081:5459344] -[Person dealloc]
14:18:48.349366+0800 aaaaaaa[73081:5459344] -第一个自动释放池销毁-
---------------------------
objc[73081]: ##############
objc[73081]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73081]: 0 releases pending.
objc[73081]: [0x105002000]  ................  PAGE  (hot) (cold)
objc[73081]: ##############
```

从上面的打印我们可以看到，在`ARC`环境中，如果对象没有被`__autoreleasing`修饰是不会被添加到自动释放池中的，这个和`MRC`中`autorelease`等价，当自动释放池超出作用域，自动释放池会销毁，池中的所有对象也会释放，这个和`MRC`是完全一样的

接下来我们再来看看`ARC`环境下的自动释放池循环嵌套情况，测试代码如下：

```
extern void _objc_autoreleasePoolPrint(void);

int main(int argc, const char * argv[]) {
    
    @autoreleasepool { // 第一个自动释放池
        // insert code here...
        
        // 注意：当前是ARC环境
                
        NSLog(@"%@", [NSThread currentThread]);
        
        Person *p1 = [[Person alloc] init];
        
        __autoreleasing Person *p2 = [[Person alloc] init];
                
        @autoreleasepool { // 第二个自动释放池
            
            __autoreleasing Dog *dog1 = [[Dog alloc] init];
            __autoreleasing Cat *cat1 = [[Cat alloc] init];
            
            _objc_autoreleasePoolPrint();
            
            NSLog(@"---------------------");
        }
        
        NSLog(@"-第二个自动释放池销毁了-");
        
        _objc_autoreleasePoolPrint();
        
        NSLog(@"---------------------");
    }
    
    NSLog(@"-第一个自动释放池销毁了-");
    
    _objc_autoreleasePoolPrint();
    return 0;
}
```

对应的终端打印如下：

```
objc[73141]: ##############
objc[73141]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73141]: 5 releases pending.
objc[73141]: [0x101804000]  ................  PAGE  (hot) (cold)
objc[73141]: [0x101804038]  ################  POOL 0x101804038
objc[73141]: [0x101804040]       0x10071cd70  Person
objc[73141]: [0x101804048]  ################  POOL 0x101804048
objc[73141]: [0x101804050]       0x10071c030  Dog
objc[73141]: [0x101804058]       0x10071d150  Cat
objc[73141]: ##############
---------------------
14:34:05.417828+0800 aaaaaaa[73141:5467454] -[Cat dealloc]
14:34:05.417890+0800 aaaaaaa[73141:5467454] -[Dog dealloc]
14:34:05.417976+0800 aaaaaaa[73141:5467454] -第二个自动释放池销毁了-
---------------------
objc[73141]: ##############
objc[73141]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73141]: 2 releases pending.
objc[73141]: [0x101804000]  ................  PAGE  (hot) (cold)
objc[73141]: [0x101804038]  ################  POOL 0x101804038
objc[73141]: [0x101804040]       0x10071cd70  Person
objc[73141]: ##############
---------------------
14:34:05.421754+0800 aaaaaaa[73141:5467454] -[Person dealloc]
14:34:05.421802+0800 aaaaaaa[73141:5467454] -[Person dealloc]
14:34:05.421872+0800 aaaaaaa[73141:5467454] -第一个自动释放池销毁了-
objc[73141]: ##############
objc[73141]: AUTORELEASE POOLS for thread 0x1000ab5c0
objc[73141]: 0 releases pending.
objc[73141]: [0x101804000]  ................  PAGE  (hot) (cold)
objc[73141]: ##############
```

我们从上面的打印可以看到，在`ARC`环境中自动释放池嵌套使用，当自动释放池超出作用域时便会销毁，池中的所有对象也都会被释放，这和`MRC`是一样的原理。

---

接下来我们再来探究下`Autorelease Pool`和`runloop`之间的关系，我们创建一个新的iOS工程，打印当前的`runloop`，测试代码如下：

```
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSLog(@"%@", [NSRunLoop currentRunLoop]);
}
@end
```

这里打印的信息太多，我们主要关心`runloop`的`Observer`的信息，核心打印如下：

```
observers = (
    "<CFRunLoopObserver 0x6000003143c0 [0x7fff805eff70]>{valid = Yes, activities = 0x1, repeats = Yes, order = -2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x600003c4f360 [0x7fff805eff70]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7fcb45001038>\n)}}",
    "<CFRunLoopObserver 0x6000003100a0 [0x7fff805eff70]>{valid = Yes, activities = 0x20, repeats = Yes, order = 0, callout = _UIGestureRecognizerUpdateObserver (0x7fff4712091e), context = <CFRunLoopObserver context 0x600001900fc0>}",
    "<CFRunLoopObserver 0x600000314280 [0x7fff805eff70]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 1999000, callout = _beforeCACommitHandler (0x7fff475a22b6), context = <CFRunLoopObserver context 0x7fcb40c00d90>}",
    "<CFRunLoopObserver 0x60000031c320 [0x7fff805eff70]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2000000, callout = _ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv (0x7fff2affcc4a), context = <CFRunLoopObserver context 0x0>}",
    "<CFRunLoopObserver 0x600000314320 [0x7fff805eff70]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2001000, callout = _afterCACommitHandler (0x7fff475a231f), context = <CFRunLoopObserver context 0x7fcb40c00d90>}",
    "<CFRunLoopObserver 0x600000314460 [0x7fff805eff70]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x600003c4f360 [0x7fff805eff70]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7fcb45001038>\n)}}"
```

上面的`observers`中，我们可以看到，程序一启动系统在主线程中就注册了如下两个`Observer`

```
// 第一个Observer
"<CFRunLoopObserver 0x6000003143c0 [0x7fff805eff70]>{valid = Yes, activities = 0x1, repeats = Yes, order = -2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x600003c4f360 [0x7fff805eff70]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7fcb45001038>\n)}}",

// 第二个Observer
"<CFRunLoopObserver 0x600000314460 [0x7fff805eff70]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x600003c4f360 [0x7fff805eff70]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7fcb45001038>\n)}}"
```

我们发现第一个Observer是用来监听`activities = 0x1`的事件，第二个Observer是用来监听`activities = 0xa0`的事件

我们再来了解下`runloop`对于监听事件状态的枚举：

```
// Run Loop Observer Activities
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),            // 1：代表是进入runloop的状态
    kCFRunLoopBeforeTimers = (1UL << 1),     // 2：即将处理timer的状态
    kCFRunLoopBeforeSources = (1UL << 2),    // 4：即将处理source的状态
    kCFRunLoopBeforeWaiting = (1UL << 5),    // 32：即将进入休眠的状态
    kCFRunLoopAfterWaiting = (1UL << 6),     // 64：已休眠，等待唤醒的状态
    kCFRunLoopExit = (1UL << 7),             // 128：退出runloop的状态
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

从枚举中对应的状态值我们便知道了，第一个`Observer`是用来监听`runloop`进入事件，也就是`kCFRunLoopEntry`，第二个Observer对应的`activities`值为0xa0=160，160正好是状态值32加上状态值128，也就是说第二个Observer是用来监听`runloop`即将进入休眠的状态`kCFRunLoopBeforeWaiting`和`runloop`退出的状态`kCFRunLoopExit`

我们通过上面的打印可以看到，这两个`Observer`当监听到事件触发，都会回调执行`callout = _wrapRunLoopWithAutoreleasePoolHandler`这个handler，从回调函数的名字`_wrapRunLoopWithAutoreleasePoolHandler`我们可以知道这个回调是用来处理`Autorelease Pool`相关操作的，那么这两个`Observer`监听到回调后会触发自动释放池的什么操作尼？

第一个`Observer`当监听到`kCFRunLoopEntry`时，这时会调用自动释放池的`objc_autoreleasePoolPush`函数，也就是创建一个自动释放池，并且将`POOL_BOUNDARY`添加到自动释放池中

第二个`Observer`当监听到`kCFRunLoopBeforeWaiting`时，这时会调用自动释放池的`objc_autoreleasePoolPop`函数，来销毁自动释放池，然后再调用`objc_autoreleasePoolPush`函数创建一个自动释放池。当监听到`kCFRunLoopExit`时，这时会调用自动释放池的`objc_autoreleasePoolPop`函数，销毁自动释放池

在`runloop`即将进入循环之前，会创建自动释放池，`runloop`退出循环会销毁自动释放池。系统之所以这样设计，其实也很好理解。因为在`runloop`即将进入循环前，系统创建了大量的事件和对象，创建的这些事件和对象最好能够由自动释放池来管理以保证得到有效的释放，然而当`runloop`退出循环，这时肯定也需要释放掉之前创建的对象，所以必然会销毁自动释放池

在`runloop`即将进入休眠状态时，这时整个应用程序都进入了休眠状态，等待其它事件来唤醒`runloop`，所以在这时也会调用`objc_autoreleasePoolPop`函数来销毁自动释放池，以保证在休眠状态下释放掉无用的对象。为了保证在下一个`runloop`循环过程中创建的事件和对象都能够及时的释放，所以在销毁完自动释放池后系统又创建了一个新的自动释放池。

我们从`Autorelease Pool`的官方文档说明中也可以看出上面`runloop`注册两个`Observer`的作用：

```
The Application Kit creates an autorelease pool on the main thread at the 
beginning of every cycle of the event loop, and drains it at the end, thereby
 releasing any autoreleased objects generated while processing an event. If 
 you use the Application Kit, you therefore typically don’t have to create 
 your own pools. If your application creates a lot of temporary autoreleased 
 objects within the event loop, however, it may be beneficial to create 
 “local” autorelease pools to help to minimize the peak memory footprint.
```

`runloop`和`Autorelease Pool`的关系如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200219-175148@2x.png)


讲解示例Demo地址：

[https://github.com/guangqiang-liu/11-AutoreleasePool]()

[https://github.com/guangqiang-liu/11.1-AutoreleasePool]()

[https://github.com/guangqiang-liu/11.2-AutoreleasePool]()

[https://github.com/guangqiang-liu/11.3-AutoreleasePool]()


## 更多文章
* ReactNative开源项目OneM(1200+star)：**[https://github.com/guangqiang-liu/OneM](https://github.com/guangqiang-liu/OneM)**：欢迎小伙伴们 **star**
* iOS组件化开发实战项目(500+star)：**[https://github.com/guangqiang-liu/iOS-Component-Pro]()**：欢迎小伙伴们 **star**
* 简书主页：包含多篇iOS和RN开发相关的技术文章[http://www.jianshu.com/u/023338566ca5](http://www.jianshu.com/u/023338566ca5) 欢迎小伙伴们：**多多关注，点赞**
* ReactNative QQ技术交流群(2000人)：**620792950** 欢迎小伙伴进群交流学习
* iOS QQ技术交流群：**678441305** 欢迎小伙伴进群交流学习