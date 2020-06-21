//
//  Person.m
//  10.4-autoreleasePool底层原理ARC
//
//  Created by 刘光强 on 2020/2/15.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import "Person.h"

@implementation Person

- (void)dealloc {
    NSLog(@"%s", __func__);
}
@end
