---
title: "手写miniVue3-07实现computed"
date: 2022-10-10T20:03:54+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## 实现`computed`
本节实现`computed()`，先看测试用例：

```typescript
describe("computed", () => {
  it("happy path", () => {
    const user = reactive({
      age: 1,
    });

    const age = computed(() => {
      return user.age;
    });

    expect(age.value).toBe(1);
  });

  it("should compute lazily", () => {
    // 计算属性的缓存特性
    const value = reactive({
      foo: 1,
    });
    const getter = jest.fn(() => {
      return value.foo;
    });
    const cValue = computed(getter);
    //cValue.value 就是那个value.foo

    // lazy -> 不获取cValue.value，getter就不会执行
    expect(getter).not.toHaveBeenCalled();

    // 触发cValue.value，get操作后获得1，并且getter执行了
    expect(cValue.value).toBe(1);
    expect(getter).toHaveBeenCalledTimes(1);

    // should not compute again
    cValue.value; // get
    expect(getter).toHaveBeenCalledTimes(1);

    // should not compute until needed
    value.foo = 2; // 触发trigger -> 收集effect -> get 重新执行
    expect(getter).toHaveBeenCalledTimes(1);

    // now it should compute
    expect(cValue.value).toBe(2);
    expect(getter).toHaveBeenCalledTimes(2);

    // should not compute again
    cValue.value;
    expect(getter).toHaveBeenCalledTimes(2);
  });
});
```
分析一下测试用例发现，`computed()`和`ref()`很像，都是返回一个带有value属性的对象，但是`computed()`具有缓存的能力，我们要完善以下细节：
1. 接受一个函数，返回一个属性，有个value属性
2. 懒执行机制，如果不获取这个value属性，则不执行传递的函数
3. 获取了这个value属性后，执行传递的函数一次，并得到返回值
4. 再次获取value属性，执行传递的函数一次，不应该计算
5. 依赖的值更新后，执行传递的函数一次，获取value属性，传递的函数调用两次
6. 再次获取value属性，传递的函数调用两次。
