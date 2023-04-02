---
title: "Vue的组件间通信"
date: 2022-12-06T20:58:23+08:00
draft: false

tags: ["vue"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

在 vue 的组件化开发的过程中，数据交互是其中很重要的环节，不同的组件间如何进行通信就是今天要探讨的话题。所谓的通信就是组件之间获取属性和调用方法的过程。
通常组件之间的关系大致可以分为: 父子组件、多级嵌套组件（也可以叫爷孙组件）、兄弟组件三大类。
本文中的 vue3 的写法都是使用<script setup>的组合式 api 的写法。

## 父子组件通信

对于父子组件通信，是最基础也是最常见的组间模式，一般常用的有三种方式：

1. props/emit
2. $parent/$children/$refs
3. $attrs/$listeners

### props/emit

vue2/vue3 都是通用的方式，基本的原理就是：

1. 父组件通过 v-bind:prop='xxx'的方式，传递给子组件，子组件通过定义好的 props 属性接受
2. 子组件不能修改 props 的值，数据流是单向的，只能是父 -> 子
3. 子组件通过$emit 方式抛出方法，父组件 v-on 监听对应的方法，对数据做处理。

对于 vue3 来说，使用 <script setup> 的组合式 API 新方式是：

```js
// 子组件
defineProps({
  msg: String,
  x: {
    type: String,
    default() {
      return "x2";
    },
  },
  y: {
    type: String,
    default() {
      return "y";
    },
  },
});

const emits = defineEmits(["showMsg"]);
emits("showMsg", title.value);

// 父组件
<template>
  <HelloWorld msg="Vite + Vue" @showMsg="showMsg" />
</template>
```

### $parent/$children/$refs

1. 对于 vue2 来说：

- 子组件获取父组件使用$parent，父组件获取子组件可以使用$children
- 同时还提供组件的引用，在子组件上加上 ref 属性，父组件便可在 mounted 生命周期中使用$refs 获取刚刚设定的那个组件，进而进行通信。

2. 对于 vue3 来说：

- 移除了$children，建议使用$refs 来获取子组件
- 不建议使用$parent，需要通过`getCurrentInstance`，进而去找到 parent
- 同时使用 <script setup> 的组合式 API 的内容都是私有的，需要通过 defineExpose()方法暴露出去
- $refs 的使用注意定义的变量要和组件上设置的 ref 属性值一样

```js
// 父组件对应的位置
<Level3 ref="level3"></Level3>;
const level3 = ref(null);
onMounted(() => {
  console.log("level3 refs is: ", level3.value);
  console.log("level3 bx is: ", level3.value.bx);
  level3.value.test333();
});

// Level3是子组件
// 使用<script setup> 的组件是默认私有的，需要暴露出去，refs才能使用
defineExpose({
  bx,
  test333,
});

// 等价于vue2中的$parent写法
const { proxy } = getCurrentInstance();
console.log("current parent is:", proxy.$parent);
```

### $attrs/$listeners

这两者是单向的，只能父 -> 子

1. 对于 vue2 来说：

- 子组件通过当前实例上的$attrs属性获取父组件中未被props消费的属性，也就this.$attrs
- 子组件通过当前实例上的$listeners属性获取父组件中未被$emit 消费的方法，也就是 this.$listeners
- 多层嵌套时可以直接通过 v-bind="$attrs"进行透传

2. 对于 vue3 来说：

- 移除了$listeners，都通过$attrs 来获取未被子组件消费的属性和方法。
- 多层嵌套时可以直接通过 v-bind="$attrs"进行透传

```js
// vue3中的子组件
const attrs = useAttrs();
// 如果父组件传递的属性和事件，没有被子组件消费掉，就在attrs里面
console.log("attrs is: ", attrs);
// 如果有多余的属性，同时子组件只有一个外层的根元素，这些属性会自动添加到根元素上
// 禁用inheritAttrs即可
<script>
export default {
  inheritAttrs: false,
};
</script>
```

## 多级嵌套组件

1. 使用 $attrs/$listeners 做透传即可，单向数据流
2. 自定义事件，注意多个监听函数的监听和销毁
3. 使用 provide/inject，这是**最推荐的方式**。

### 自定义事件

1. 对于 vue2 来说：

- 通过全局的 new Vue()作为 eventBus
- 子组件利用$emit()
- 父组件利用$on()， beforeDestroy 中$off()销毁

2. 对于 vue3 来说：

- 需要借助第三方的 event-emitter 库
- 子组件 emit()
- 父组件 on(), onBeforeUnmount()中 off 销毁

### provide/inject

就是依赖注入的方式，父组件 provide 值，子组件 inject 值

```js
// vue3中的父组件
import { computed, onBeforeUpdate, onMounted, provide, ref } from "vue";

const provideValue2 = ref("我给你注入个值");
provide("hello2", {
  provideValue: computed(() => provideValue2.value), // 带计算缓存的值
  getB, // 方法
});

// vue3中的子组件
// 使用inject
const { provideValue } = inject("hello2");
```

## 兄弟组件

一般来说有两种方式：

1. 使用全局自定义事件
2. 使用 vuex
