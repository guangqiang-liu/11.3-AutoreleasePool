//
//  main.m
//  10.4-autoreleasePool底层原理ARC
//
//  Created by 刘光强 on 2020/2/15.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Person.h"


extern void _objc_autoreleasePoolPrint(void);


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
        
        _objc_autoreleasePoolPrint();
        
        Person *p1 = [[Person alloc] init];
        
        // 在ARC中，只要对象使用__autoreleasing修饰，就会将这个对象添加到自动释放池中，不使用这个修饰的就不会添加到自动释放池中
        __autoreleasing Person *p2 = [[Person alloc] init];
        
        _objc_autoreleasePoolPrint();
        
        // 使用__weak修饰的对象，没有添加到自动释放池中
        __weak typeof(Person) *weakP = p1;
        
        _objc_autoreleasePoolPrint();
        
        // ARC有效时，用@autoreleasepool块替代NSAutoreleasePool类，用__autoreleasing修饰符的变量替代autorelease方法
        @autoreleasepool {
            // 嵌套一个自动释放池，对象没有被__autoreleasing修饰，还是没有添加到自动释放池中，池中只是多了一个哨兵对象入栈了
            Person *p5 = [[Person alloc] init];
            
            _objc_autoreleasePoolPrint();
        }
        
        // 通过打印我们发现，在ARC中，创建的对象都没有办法调用autorelease，所以打印自动释放池中的内容，也看不到创建的对象，那ARC中是怎么做到内存管理的尼？
        
        // ARC之所以能做到自动引用计数器管理，也就是说自动进行内存管理，基本上都是编辑器在编译阶段帮我们做了很多内存管理的工作，准确的说是编译器和runtime一同工作完成ARC的内存管理
        
        __autoreleasing NSObject *obj1 = [[NSObject alloc] init];
        
        NSObject *obj2 = [[NSObject alloc] init];
        
        _objc_autoreleasePoolPrint();
    }
    
    _objc_autoreleasePoolPrint();
    
    __autoreleasing Person *p3 = [[Person alloc] init];
    
    _objc_autoreleasePoolPrint();
    
    NSObject *obj3 = [[NSObject alloc] init];
    
    _objc_autoreleasePoolPrint();
    return 0;
}


/**
 ARC 模式下在方法 return 的时候，会调用 objc_autoreleaseReturnValue()
 方法替代 autorelease。在调用者强引用方法返回对象的时候，会调用 objc_retainAutoreleasedReturnValue() 方法
 
 NSMutableArray *array = objc_msgSend(NSMutableArray, @selector(array));
 objc_retainAutoreleasedReturnValue(array);
 objc_release(array);
 
 
 id __weak obj1 = obj0;
 NSLog(@"class=%@", [obj1 class]);
 // 等同于：
 id __weak obj1 = obj0;
 id __autoreleasing tmp = obj1;
 NSLog(@"class=%@", [tmp class]);
 
 这种代码是如何转得到的？？？ 这种代码是伪代码，是根据编译器伪造出来的代码
 
 
 创建的属性对象，可以调用autorelease，让自动释放池来管理对象的生命周期吗？
    这个是不行的，因为属性不是一个对象，他只是一个指针，只有对这个属性赋值后，他才能有意义
 */
