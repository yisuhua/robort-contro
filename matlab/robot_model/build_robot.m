% 六轴工业机械臂：第 1 课——建立简化运动学模型
% 项目：工业机器人 | GitHub: yisuhua/robort-contro
% 范围：正运动学、关节运动、简化外观和基础解析检查
% 注意：关节轴线的详细实现仍为 PROPOSED；本文件不代表真实 CAD 或动力学验证。

clear;
clc;
close all;

%% 1. 检查 Robotics System Toolbox
if isempty(which('rigidBodyTree')) || isempty(which('trvec2tform'))
    error('未找到 Robotics System Toolbox 所需函数，请检查 MATLAB 工具箱安装和许可证。');
end

%% 2. 确定几何参数（单位：m）
d1 = 0.320;  % 基座到肩部高度，已确认
a1 = 0.080;  % J1 轴到肩部水平偏置，已确认
L2 = 0.350;  % J2 到 J3 的中心距，已确认
L3 = 0.340;  % J3 到腕心的中心距，已确认
L4 = 0.130;  % 腕心到工具法兰的距离，已确认

% 每行分别对应 J1~J6 的局部旋转轴（候选骨架）
jointAxes = [
    0 0 1;  % J1：绕 Z 轴
    0 1 0;  % J2：绕 Y 轴
    0 1 0;  % J3：绕 Y 轴
    1 0 0;  % J4：绕 X 轴
    0 1 0;  % J5：绕 Y 轴
    1 0 0   % J6：绕 X 轴
];

% 每行对应一个关节相对于上一个刚体坐标系的固定平移（m）
jointOffsets = [
    0   0  0;
    a1  0  d1;
    L2  0  0;
    L3  0  0;
    0   0  0;
    0   0  0
];

%% 3. 创建机器人：六个转动关节
robot = rigidBodyTree('DataFormat','column');
parentName = robot.BaseName;

for k = 1:6
    bodyName = sprintf('link%d',k);
    jointName = sprintf('joint%d',k);

    body = rigidBody(bodyName);
    joint = rigidBodyJoint(jointName,'revolute');

    % 设置关节绕自身局部坐标系的哪个轴转动
    joint.JointAxis = jointAxes(k,:);

    % 将当前关节放在父刚体的对应位置；不引入固定旋转
    setFixedTransform(joint,trvec2tform(jointOffsets(k,:)));

    % 仅 J1 的实际机械角度范围已确认
    if k == 1
        joint.PositionLimits = [-170 170] * pi / 180;
    end
    % J2~J6 的默认范围只是软件默认值，不是实际机械限位

    body.Joint = joint;

    % 仅添加用于观察的外形，不是碰撞几何，也不是质量惯量模型
    switch k
        case 1
            addVisual(body,'Box',[0.07 0.07 d1], ...
                trvec2tform([0 0 d1/2]));
            addVisual(body,'Box',[0.16 0.08 0.05], ...
                trvec2tform([a1/2 0 d1]));
        case 2
            addVisual(body,'Box',[L2 0.04 0.04], ...
                trvec2tform([L2/2 0 0]));
        case 3
            addVisual(body,'Box',[L3 0.04 0.04], ...
                trvec2tform([L3/2 0 0]));
        otherwise
            addVisual(body,'Box',[0.06 0.06 0.06],eye(4));
    end

    addBody(robot,body,parentName);
    parentName = bodyName;
end

%% 4. 添加固定工具法兰（不是第七个自由度）
tool = rigidBody('tool_flange');
toolJoint = rigidBodyJoint('tool_fixed','fixed');
setFixedTransform(toolJoint,trvec2tform([L4 0 0]));
tool.Joint = toolJoint;
addVisual(tool,'Box',[0.012 0.09 0.09],eye(4));
addBody(robot,tool,'link6');

%% 5. 查看机器人结构和零位末端位姿
showdetails(robot);
q0 = homeConfiguration(robot);  % DataFormat=column -> 6×1 列向量
assert(numel(q0)==6,'关节数错误：应有六个可动关节。');

T0 = getTransform(robot,q0,'tool_flange');
p0 = T0(1:3,4);

fprintf('\n零位工具法兰位置 [x y z]（m）：\n');
disp(p0.');

%% 6. 独立位置与旋转矩阵检查
tol = 1e-10;  % 纯数学几何一致性阈值，不是机器人定位精度
expected0 = [a1+L2+L3+L4; 0; d1];
assert(norm(p0-expected0)<tol,'零位位置不符合几何骨架。');

% J1 绕世界 Z 轴转动 90°
qJ1 = zeros(6,1);
qJ1(1) = pi/2;
TJ1 = getTransform(robot,qJ1,'tool_flange');
pJ1 = TJ1(1:3,4);
expectedJ1 = [0; a1+L2+L3+L4; d1];
assert(norm(pJ1-expectedJ1)<tol,'J1 转动方向或偏移存在问题。');

% J3 绕局部 Y 轴转动 -90°，把前臂及法兰转向 +Z
qJ3 = zeros(6,1);
qJ3(3) = -pi/2;  % 数学检验姿态，不代表实际 J3 限位已确认
TJ3 = getTransform(robot,qJ3,'tool_flange');
pJ3 = TJ3(1:3,4);
expectedJ3 = [a1+L2; 0; d1+L3+L4];
assert(norm(pJ3-expectedJ3)<tol,'J3 转动方向或中心距存在问题。');

% J4 纯滚转：法兰位置保持不变，但姿态发生变化
qJ4 = zeros(6,1);
qJ4(4) = pi/6;
TJ4 = getTransform(robot,qJ4,'tool_flange');
assert(norm(TJ4(1:3,4)-p0)<tol,'J4 滚转不应改变此模型中的法兰位置。');
assert(norm(TJ4(1:3,1:3)-T0(1:3,1:3),'fro')>1e-6, ...
    'J4 滚转后姿态应发生变化。');

R0 = T0(1:3,1:3);
assert(norm(R0.'*R0-eye(3),'fro')<tol,'旋转矩阵不正交。');
assert(abs(det(R0)-1)<tol,'旋转矩阵行列式不为 1。');

fprintf('解析几何检查通过：零位、J1、J3、J4。\n');
fprintf('J1 90° 后法兰位置（m）：\n');
disp(pJ1.');
fprintf('J3 -90° 后法兰位置（m）：\n');
disp(pJ3.');

%% 7. 显示两种姿态
figure('Name','六轴机械臂：零位','Color','w');
show(robot,q0,'Frames','all','Visuals','on');
axis equal;
grid on;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
title('六轴简化机构：零位');
view(35,25);

figure('Name','六轴机械臂：J3 -90 deg','Color','w');
show(robot,qJ3,'Frames','all','Visuals','on');
axis equal;
grid on;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
title('六轴简化机构：J3 绕 Y 轴转动 -90°（数学检查姿态）');
view(35,25);

disp('脚本结束。注意：尚未进行碰撞、动力学、轨迹控制或真实 MATLAB 环境验收。');
