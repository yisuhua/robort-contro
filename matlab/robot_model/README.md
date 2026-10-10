# 第一课：六轴机械臂运动学入门（PROPOSED）

本目录属于工业机器人 Project，与其他项目隔离。代码入口：[`build_robot.m`](./build_robot.m)。

## 环境要求
- MATLAB
- Robotics System Toolbox
- 需要能够显示 MATLAB 图形窗口。
- **实际 MATLAB 运行状态：NOT RUN**；当前仅完成官方 API 查证、GitHub 文件回读，以及基于独立 Python 齐次变换的理论点数值校验。

## 运行
1. 在 GitHub Desktop 中克隆 `yisuhua/robort-contro`（请注意仓库实际拼写为 `robort-contro`）。
2. 在 MATLAB 中打开 `matlab/robot_model/build_robot.m`。
3. 在命令行运行 `ver`，确认安装 Robotics System Toolbox。
4. 单击编辑器的 **Run**。
5. 检查命令行输出；应有六个 revolute 关节、一个 fixed 法兰连接，并打开两幅姿态图。

## 已确认几何输入（单位 m）
| 参数 | 数值 | 意义 |
| --- | ---: | --- |
| d1 | 0.320 | 基座→肩部高度 |
| a1 | 0.080 | J1→肩部水平偏置 |
| L2 | 0.350 | J2→J3 |
| L3 | 0.340 | J3→腕心 |
| L4 | 0.130 | 腕心→法兰 |

详细关节轴线和零位坐标属于 **PROPOSED** 的运动学实现，尚未获得真实 CAD 轴线比对的验证。

## 数学结构
旋转关节的运动输入为弧度，关节轴线依次为：
`Z, Y, Y, X, Y, X`。

相对于每个父刚体的关节平移依次为：
`[0 0 0]`,
`[a1 0 d1]`,
`[L2 0 0]`,
`[L3 0 0]`,
`[0 0 0]`,
`[0 0 0]`。

末端位置姿态对应一个 4×4 齐次变换：
```text
T = [R(3x3)  p(3x1)]
    [0 0 0    1     ]
```
其中 `R` 表示末端方向，`p` 表示相对世界坐标的末端位置。

一个关节的空间变换包括 **固定平移** 和 **随关节角变化的旋转**。完整末端变换由这些关节变换依次相乘，再加上腕心→法兰的固定偏移得到。

## 解析校验点
| 测试 | 预期法兰位置，m | 用途 |
| --- | --- | --- |
| 所有关节 0 | (0.900, 0, 0.320) | 验证所有几何尺寸和 |
| 仅 J1=+90° | (0, 0.900, 0.320) | 验证 J1 的 Z 轴方向 |
| 仅 J3=-90° | (0.430, 0, 0.790) | 验证 J3 的 Y 轴方向与剩余伸出长度 |
| 仅 J4=+30° | (0.900, 0, 0.320)，姿态变化 | 区分位置与姿态 |

代码中 `tol=1e-10` m 是 **纯数学一致性检查阈值**，并不是机器人定位精度。J3=-90° 属于数学测试姿态，不代表实际机械允许到达。J2~J6 的 MATLAB 默认关节限制也不是当前 Project 的真实机械限位。

## 关键 MATLAB 对象
- `rigidBodyTree`：表示全机器人运动树。
- `rigidBody`：表示每个随关节运动的刚体。
- `rigidBodyJoint`：定义固定、旋转等连接。
- `JointAxis`：定义转动方向。
- `setFixedTransform`：定义关节相对于其父刚体的固定位置。
- `addBody`：按父子关系把刚体接入运动树。
- `addVisual`：仅绘制外形，不自动建立碰撞约束或物理惯性。
- `homeConfiguration`：读取零位关节配置。
- `getTransform`：计算末端相对机器人基座的 4×4 齐次变换。
- `show`：显示模型，`showdetails`：打印运动树层级。
- `assert`：如果解析校验不通过，立即停止并报告错误。

## 本阶段边界
- 几何参数来源：当前工业机器人 Project 已确认的尺寸。
- J1 限位 ±170° 已确认；其他关节的物理限位尚未确认。
- 简化方块只用于视觉显示，不具备真实质量、惯量、碰撞体或力学计算能力。
- **不等于**完成逆运动学、避障规划、动力学模型、控制性能或实物验证。
- MATLAB 中仍需要由使用者实际运行及记录截图/命令行结果。

## 官方参考
- [MathWorks rigidBodyTree](https://www.mathworks.com/help/robotics/ref/rigidbodytree.html)
- [MathWorks rigidBodyJoint](https://www.mathworks.com/help/robotics/ref/rigidbodyjoint.html)
- [MathWorks setFixedTransform](https://www.mathworks.com/help/robotics/ref/rigidbodyjoint.setfixedtransform.html)
- [MathWorks addVisual](https://www.mathworks.com/help/robotics/ref/rigidbody.addvisual.html)
- [MathWorks getTransform](https://www.mathworks.com/help/robotics/ref/rigidbodytree.gettransform.html)
