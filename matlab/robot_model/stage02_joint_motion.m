% 六轴工业机械臂：第二课——逐关节运动验证与动画
% 前置条件：在当前 MATLAB 会话中先运行 build_robot.m
% 本课不改变第一课中的几何参数、转轴或关节连接关系。
% 只研究正运动学；不是闭环控制，也不代表关节限位/碰撞已验证。

%% 1. 检查第一课的模型是否已经建立
if ~exist('robot','var') || ~isa(robot,'rigidBodyTree')
    error('未找到 robot。请先在同一 MATLAB 会话中运行 build_robot.m。');
end
if robot.NumBodies ~= 7 || ~strcmp(robot.DataFormat,'column') || ...
        ~ismember('tool_flange',robot.BodyNames)
    error('当前 robot 不是第一课的六轴模型，请重新运行 build_robot.m。');
end

qHome = homeConfiguration(robot);
if numel(qHome) ~= 6
    error('机器人应有 6 个独立旋转关节。');
end
qHome = qHome(:);
if norm(qHome) > 1e-12
    error('第一课候选模型的零位应为六关节角均为 0。');
end

THome = getTransform(robot,qHome,'tool_flange');
pHome = THome(1:3,4);
tol = 1e-10;
assert(norm(pHome-[0.900;0;0.320]) < tol, ...
    '当前模型与第一课已经通过的零位几何检查不一致。');

%% 2. 设计逐关节往返的教学轨迹
% 角度仅为运动学演示输入；J2~J6 实际机械限位尚未确定。
jointAmplitudeDeg = [30; -25; -35; 30; 20; 40];
framesPerJoint = 31;                 % 每个关节的采样帧数（奇数，中间帧到峰值）
totalFrames = 6 * framesPerJoint;

qHistory = zeros(6,totalFrames);     % 每一列：6 个关节角度（rad）
tcpHistory = zeros(3,totalFrames);   % 每一列：法兰位置（m）
zyxHistory = zeros(3,totalFrames);   % 每一列：[Z Y X] 欧拉角（rad）

%% 3. 创建动画 Figure
fig = figure('Name','第二课：六轴逐关节运动','Color','w');
ax = axes('Parent',fig);

show(robot,qHome,'Parent',ax, ...
    'Frames','off','Visuals','on','PreservePlot',false);
axis(ax,[-1.05 1.05 -1.05 1.05 -0.15 1.25]);
axis(ax,'equal');
grid(ax,'on');
view(ax,35,25);
xlabel(ax,'X (m)');
ylabel(ax,'Y (m)');
zlabel(ax,'Z (m)');

%% 4. 按 J1 -> J6 顺序分别运动
index = 0;
for jointIndex = 1:6
    fprintf('\n开始检查 J%d（峰值 %+.1f deg）\n', ...
        jointIndex,jointAmplitudeDeg(jointIndex));

    for frameIndex = 1:framesPerJoint
        index = index + 1;

        % 归一化帧位置 u 属于 [0,1]
        u = (frameIndex-1) / (framesPerJoint-1);

        % 从 0 平滑到 1 再平滑回 0，端点变化率为 0
        s = (1-cos(2*pi*u))/2;

        % 每次仅使一个关节运动，其他五个保持零位
        q = zeros(6,1);
        q(jointIndex) = jointAmplitudeDeg(jointIndex)*pi/180*s;

        % 关节空间角度 -> 末端的齐次变换
        T = getTransform(robot,q,'tool_flange');
        p = T(1:3,4);
        R = T(1:3,1:3);

        % 数学检查：R 必须是合法旋转矩阵
        assert(norm(R.'*R-eye(3),'fro') < 1e-9, ...
            '发现不满足正交性的旋转矩阵。');
        assert(abs(det(R)-1) < 1e-9, ...
            '发现行列式不为 1 的旋转矩阵。');

        % 姿态采用 ZYX 欧拉角：第1项绕Z，第2项绕Y，第3项绕X
        eul = rotm2eul(R,'ZYX');

        % 保存这一帧的计算结果
        qHistory(:,index) = q;
        tcpHistory(:,index) = p;
        zyxHistory(:,index) = eul(:);

        % 更新画面：不要保留上一帧的机器人图形
        if ~ishandle(fig)
            error('动画窗口已被关闭；请重新运行第二课脚本。');
        end
        show(robot,q,'Parent',ax, ...
            'Frames','off','Visuals','on','PreservePlot',false);
        title(ax,sprintf( ...
            'J%d: %+.1f deg | TCP = (%.3f, %.3f, %.3f) m', ...
            jointIndex,q(jointIndex)*180/pi,p(1),p(2),p(3)));
        drawnow;
        pause(0.02);  % 控制观看速度，不代表真实机器人采样周期
    end
end

%% 5. 定量验证：每个关节都应改变末端姿态
positionChange = zeros(6,1);
orientationChangeDeg = zeros(6,1);
RHome = THome(1:3,1:3);

for jointIndex = 1:6
    qPeak = zeros(6,1);
    qPeak(jointIndex) = jointAmplitudeDeg(jointIndex)*pi/180;
    TPeak = getTransform(robot,qPeak,'tool_flange');

    positionChange(jointIndex) = ...
        norm(TPeak(1:3,4)-pHome);

    RRelative = RHome.' * TPeak(1:3,1:3);
    cosine = (trace(RRelative)-1)/2;
    cosine = min(1,max(-1,cosine));  % 抑制浮点舍入导致的 acos 越界
    orientationChangeDeg(jointIndex) = acos(cosine)*180/pi;
end

% 当前相交球腕骨架：J4、J6 绕末端轴滚转，法兰位置保持不变
assert(all(positionChange([4 6]) < tol), ...
    'J4/J6 应仅使法兰改变姿态，不改变法兰位置。');
assert(all(positionChange([1 2 3 5]) > 1e-5), ...
    'J1/J2/J3/J5 的演示运动应改变法兰位置。');
assert(all(orientationChangeDeg > 1), ...
    '每个关节在教学测试角度下都应改变法兰姿态。');

fprintf('\n各关节在峰值角度下的末端变化：\n');
fprintf('  关节    位置位移(m)    相对姿态角(deg)\n');
for jointIndex = 1:6
    fprintf('   J%d       %.6f          %.3f\n', ...
        jointIndex,positionChange(jointIndex), ...
        orientationChangeDeg(jointIndex));
end

%% 6. 绘制六个关节角度曲线
frame = 1:totalFrames;

figure('Name','第二课：六轴关节角度','Color','w');
plot(frame,qHistory.'*180/pi,'LineWidth',1.3);
grid on;
xlabel('动画帧编号（不是物理时间）');
ylabel('关节角度 (deg)');
title('J1~J6 分别从零位运动并返回');
legend({'J1','J2','J3','J4','J5','J6'},'Location','best');

%% 7. 绘制法兰位置轨迹
figure('Name','第二课：末端法兰空间轨迹','Color','w');
plot3(tcpHistory(1,:),tcpHistory(2,:),tcpHistory(3,:), ...
    'LineWidth',1.5);
hold on;
plot3(pHome(1),pHome(2),pHome(3),'ko', ...
    'MarkerSize',6,'MarkerFaceColor','k');
hold off;
grid on;
axis equal;
xlabel('X (m)');
ylabel('Y (m)');
zlabel('Z (m)');
title('逐关节运动产生的法兰位置轨迹');

%% 8. 绘制末端姿态（ZYX 欧拉角）
figure('Name','第二课：末端姿态','Color','w');
plot(frame,zyxHistory.'*180/pi,'LineWidth',1.3);
grid on;
xlabel('动画帧编号（不是物理时间）');
ylabel('姿态角 (deg)');
title('法兰相对基座的 ZYX 欧拉角');
legend({'Z / yaw','Y / pitch','X / roll'},'Location','best');

disp('第二课脚本结束：本次数学检查通过。');
disp('注意：动画不是动力学或闭环控制仿真；实际机械限位仍需核实。');
