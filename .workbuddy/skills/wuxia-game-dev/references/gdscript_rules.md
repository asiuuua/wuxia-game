# GDScript 4.x 硬规（高频坑速查）

> 与 Godot 4.7.2 实测相关；违反即 Parse/Compile Error 或运行时崩。改代码前过一遍。

## 一、class_name 与 const

- **autoload 禁写同名 `class_name`**：autoload 单例已全局可见，再声明 `class_name` 会冲突。
- `const X = preload("res://...")` 与全局 `class_name X` 会 **shadowed**（局部 const 遮蔽全局类）。子类 `extends PopupBase` 后**不要重复声明父类的 `const UICenterUtils`**（报错 "The member UICenterUtils already exists in parent class"）。

## 二、数组与类型

- untyped `Array` 遍历出 `Variant` → 显式标类型 `for x in arr:` 改为 `for x: MyType in arr:` 或声明 `var arr: Array[MyType]`。
- **typed Array 禁 `as Array[String]`**（直接崩）→ 用循环 `append` 逐个装。
- `mini(a,b)` / `maxi(a,b)` **仅 2 参**；求多参最值需嵌套 `maxi(maxi(a,b),c)`。写三参 `maxi(a,b,c)` 是 Parse Error，且会级联拖垮依赖它的存档套件。

## 三、语法与格式

- **tab 缩进**（非空格）。
- 函数体**不能空**：占位用 `pass`。
- 场景树忙（初始化/删除节点）用 `call_deferred`，勿同步改树。
- 删函数/信号后须**全工程 grep 残留调用**；`Invalid call Nonexistent function 'new'` 真因往往是某脚本有 Parse Error 导致类未注册。

## 四、@warning_ignore 位置

- 顶层声明（如 `@warning_ignore("shadowed_global_identifier")`）须**列首、无缩进**。
- 类级注解（如 `@warning_ignore("unused_signal")`）写在 `extends` **之前**。
- autoload 的 signal 须**逐条**加 `@warning_ignore("unused_signal")`，否则编译告警（门禁可能计错）。

## 五、Control 变换

- `Control.scale` 以 `pivot_offset` 为基准（默认左上角）→ 悬停放大先 `pivot_offset = size/2` 并监听 `resized` 更新中心，否则放大从左上角炸开。

## 六、测试框架特殊限制（TestBase）

- `run_all.tscn` **同步** `inst.run()`，**不 await**；用例不要在测试内 `await`。
- **测试内不能用 lambda 捕获外层局部变量**（GDScript 4.7.2 失效）→ 把数据写成实例属性或闭包外变量。
- 断言用 `expect(cond, msg)`；失败在 `run_all` 输出 `✗ <msg>`。

## 七、加载与资源

- 运行时加载优先 `preload`（编译期，确定存在）或 `load`（运行期）；引用单例（如 `UIManager`）直接全局名，无需 preload（它是 autoload 单例，非必须 `const` 声明）。
- 单脚本 `--check-only --script res://<path>.gd` **不加载 autoload**，引用单例会报假阳性，仅用于查本文件语法行号。

## 八、信号连接

- 首选 `signal.connect(cb)` 或 `obj.signal.connect(caller.method)`；断开在 `_exit_tree` 统一处理（UI 面板订阅 EventBus 须 `_exit_tree` 断信号，防重复触发）。
