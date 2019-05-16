//
//  NSObject+IQDataBinding.m
//  IQDataBinding
//
//  Created by lobster on 2019/5/2.
//  Copyright © 2019 lobster. All rights reserved.
//

#import "NSObject+IQDataBinding.h"
#import <objc/runtime.h>

static NSString *kViewAssociatedModelKey = @"kViewAssociatedModelKey";
static NSMutableDictionary *stashedObserver = nil;

@interface IQWatchDog : NSObject

@property (nonatomic, weak) id target;
@property (nonatomic, strong) NSMutableDictionary *keyPathsAndCallBacks;

@end

@implementation IQWatchDog

- (void)dealloc {
    [self.keyPathsAndCallBacks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [self.target removeObserver:self forKeyPath:key];
    }];
}

- (void)observeKeyPath:(NSString *)keyPath callBack:(observerCallBack)callBack {
    NSAssert(keyPath.length, @"keyPath不合法");
    /*加载默认值*/
    id value = [self.target valueForKeyPath:keyPath];
    if (value) {
        callBack(value);
    }
    /*添加观察者*/
    [self.keyPathsAndCallBacks setObject:callBack forKey:keyPath];
    [self.target addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    observerCallBack callBack = self.keyPathsAndCallBacks[keyPath];
    if (callBack) {
        callBack(change[NSKeyValueChangeNewKey]);
    }
}

- (void)removeAllObservers {
    [self.keyPathsAndCallBacks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [self.target removeObserver:self forKeyPath:key];
    }];
}

- (NSMutableDictionary *)keyPathsAndCallBacks {
    if (!_keyPathsAndCallBacks) {
        _keyPathsAndCallBacks = [NSMutableDictionary dictionary];
    }
    return _keyPathsAndCallBacks;
}

@end

@implementation NSObject (IQDataBinding)

- (void)bindModel:(id)model {
    /*给view添加一个关联对象IQWatchDog，IQWatchDog职责如下
     1.存储@{绑定的Key，回调Block}对应关系。
     2.根据@{绑定的Key，回调Block}中的Key，进行KVO监听。
     3.监听view Dealloc事件，自动移除KVO监听。
     */
    IQWatchDog *viewAssociatedModel = objc_getAssociatedObject(self, &kViewAssociatedModelKey);
    if (!viewAssociatedModel) {
        viewAssociatedModel = [[IQWatchDog alloc]init];
        viewAssociatedModel.target = model;
        objc_setAssociatedObject(self, &kViewAssociatedModelKey, viewAssociatedModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    if (viewAssociatedModel.target) {
        //如果有view的关联model，则先把观察model的操作移除掉
        [viewAssociatedModel removeAllObservers];
    }
    
    /*借鉴Git stash暂存命令理念，stashedObserver职责如下
     1.如果bindModel调用在绑定keyPath之后调用，会自动把当前@{绑定的Key，回调Block}结构保存到暂存区。
     2.调用bindModel的时候先根据当前view的地址指针去stashedObserver取暂存的数据。
     3.如果暂存区有数据则调用IQWatchDog注册方法进行自动注册。
     4.注册完成进行stash pop操作。
     */
    NSString *viewP = [NSString stringWithFormat:@"%p",self];
    
    NSDictionary *viewStashMap = stashedObserver[viewP];
    
    if (viewStashMap) {
        [viewStashMap enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [viewAssociatedModel observeKeyPath:key callBack:obj];
        }];
        /*stash pop*/
        [stashedObserver removeObjectForKey:viewP];
    }
}

- (NSObject *(^)(NSString *keyPath,observerCallBack observer))bind {
    
    if (!stashedObserver) {
        stashedObserver = [NSMutableDictionary dictionary];
    }
    
    IQWatchDog *viewAssociatedModel = objc_getAssociatedObject(self, &kViewAssociatedModelKey);
    return ^(NSString *keyPath,observerCallBack observer){
        /*viewAssociatedModel为空，说明在绑定属性前没有绑定model，此处进行stash暂存*/
        if (!viewAssociatedModel) {
            /*stash push*/
            NSString *viewP = [NSString stringWithFormat:@"%p",self];
            NSMutableDictionary *viewStashMap = [NSMutableDictionary dictionaryWithDictionary:stashedObserver[viewP]];
            
            if (!viewStashMap) {
                viewStashMap = [NSMutableDictionary new];
            }
            
            [viewStashMap setObject:observer forKey:keyPath];
            
            [stashedObserver setObject:viewStashMap forKey:viewP];
            return self;
        }
        [viewAssociatedModel observeKeyPath:keyPath callBack:observer];
        return self;
    };
}

- (void)updateValue:(id)value forKeyPath:(NSString *)keyPath {
#warning fix me！！直接setvalue会触发KVO，导致死循环
    IQWatchDog *viewAssociatedModel = objc_getAssociatedObject(self, &kViewAssociatedModelKey);
    [viewAssociatedModel.target setValue:value forKey:keyPath];
#warning TODO 可以用不定参数来解决传输不同类型数据问题。
#warning TODO object_setIvar函数只支持设置id类型，需要根据不定参数进行函数强转。
#warning 采用函数式编程思路进行设置
//    Ivar ivar = class_getInstanceVariable([viewAssociatedModel.target class], [keyPath UTF8String]);
//    void (*f)(id, Ivar, float) = (void (*)(id, Ivar, float))object_setIvar;
//    object_setIvar(viewAssociatedModel.target, ivar, value);
//    f(viewAssociatedModel.target, ivar, value);
    
}

- (NSObject * (^)(id,...))update {
    return ^id(id attribute,...) {
        return self;
    };
}


@end
