# 第二课：六关节独立运动验证（PROPOSED）

代码入口：[`stage02_joint_motion.m`](./stage02_joint_motion.m)。保持第一课 `build_robot.m` 不变。

## 运行
1. 进入 MATLAB，在与第一课相同的目录打开 `build_robot.m`，完整执行，确保工作区里出现变量 `robot`。
2. 不要在两次运行之间输入 `clear`、`clear all` 或重启 MATLAB；第二课脚本**复用第一课已构建的 `robot` 对象**。
3. 新建/打开 `stage02_joint_motion.m`，点击 **Run**。
4. 观察依次 J1→J6 运动的动画，以及脚本结束后生成的关节角度、TCP 空间轨迹和 ZYX 姿态曲线图。
5. 若没有 `robot`，先重跑第一课；若弹出 API 错误，保留完整错误消息与 MATLAB 版本号，不要修改几何数据、降低判据。

## 关键学习目标
- 关节空间配置：`q=[q1;q2;q3;q4;q5;q6]`，单位 rad。
- 只改变 `q(k)`，其他五轴角度为 0，以避免多个关节同时运动时难以辨认运动原因。
- 一段往返动作使用 `s(u)=(1-cos(2*pi*u))/2`，其中 `u∈[0,1]`，序列起点、终点均为 0、中点为 1，端点对 u 的导数为 0。
- 正运动学：`T=getTransform(robot,q,'tool_flange')`。位置 `p=T(1:3,4)`，姿态 `R=T(1:3,1:3)`。
- `rotm2eul(R,'ZYX')` 依次返回 Z、Y、X 欧拉角，**不等于六个关节角，也不是逐轴驱动命令**。
- `show(...,'Frames','off','Visuals','on','PreservePlot',false)` 适配先前 MATLAB 错误中确认的 `Frames` 取值 `on/off`，通过替换旧机器人图元显示连续运动。

## 第一课已确认的几何输入
- `d1=0.320` m，`a1=0.080` m；
- `L2=0.350` m，`L3=0.340` m，`L4=0.130` m。
- 六关节局部轴顺序：Z/Y/Y/X/Y/X。
- 以上局部轴线的详细零位定义属于 **PROPOSED 实现**，尚未与真实 CAD 轴线逐项核验。
- J1 范围 ±170° 已确认。其他轴真实限位未知。

## 独立计算的预期峰值效果（非 MATLAB 实测）
| 关节 | 输入峰值 (deg) | 法兰相对零位的位置变化 (m) | 相对零位的姿态角 (deg) |
| --- | ---: | ---: | ---: |
| J1 | +30 | 0.465874 | 30 |
| J2 | -25 | 0.354961 | 25 |
| J3 | -35 | 0.282663 | 35 |
| J4 | +30 | 0 | 30 |
| J5 | +20 | 0.045149 | 20 |
| J6 | +40 | 0 | 40 |

预测由当前简化骨架的独立齐次变换数值计算得到；J4/J6 与工具法兰 X 轴共线，因此只改变方向、不改变法兰原点位置。模型真正包含电机、外形碰撞及惯性后，可能发生更多约束，但不更改本次数学参考值。

## 输出文件与状态
- 输出主要在 MATLAB figure 窗口与工作区，不自动保存图片或 CSV。
- 本脚本 **没有真实时间轴**。横轴为帧编号，`pause(0.02)` 是展示节奏，不是伺服周期。
- 未指定质量和惯量，不验证动力学。
- `addVisual` 的盒体仅用于显示，不代表已建立可靠碰撞几何。
- J2~J6 的示范角度不表示真实关节机械限制已核实，也不能据此宣称无碰撞。
- MATLAB 本机实跑状态：**NOT RUN**。需要保存用户的成功日志或错误反馈后才能更新。
- 该课重点是**运动学验证**，并非闭环控制、规划或真实 TCP 性能试验。

## MATLAB 官方参考
- [rigidBodyTree.show：动画、Parent 和 PreservePlot](https://www.mathworks.com/help/robotics/ref/rigidbodytree.show.html)
- [rigidBodyTree.getTransform：求解末端位姿](https://www.mathworks.com/help/robotics/ref/rigidbodytree.gettransform.html)
- [rotm2eul：ZYX 姿态角](https://www.mathworks.com/help/robotics/ref/rotm2eul.html)
