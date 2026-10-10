% 六轴工业机械臂：第三课——逆运动学与末端直线轨迹
% 前提：先在同一 MATLAB 工作区运行第一课 build_robot.m
% 模型参数保持不变。本课不做避障、动力学或闭环控制。
% 本脚本中的起点关节角仅是数学演示姿态；不代表机械限位已确认。

%% 1. 检查第一课的机器人对象
if ~exist('robot','var') || ~isa(robot,'rigidBodyTree')
    error('工作区没有 robot。请先运行 build_robot.m，且不要在中间执行 clear。');
end
if robot.NumBodies ~= 7 || ~strcmp(robot.DataFormat,'column') || ...
        ~ismember('tool_flange',robot.BodyNames)
    error('当前 robot 不是第一课约定的六轴机器人模型。');
end
qHome = homeConfiguration(robot);
assert(numel(qHome)==6,'机器人应有六个可动关节。');
THome = getTransform(robot,qHome,'tool_flange');
assert(norm(THome(1:3,4)-[0.900;0;0.320]) < 1e-10, ...
    '检测到模型几何与第一课已通过的基线不一致。');

%% 2. 创建逆运动学求解器
% 权重前三项对应姿态误差，后三项对应 XYZ 位置误差
ik = inverseKinematics('RigidBodyTree',robot);
weights = [1 1 1 1 1 1];

% 若当前版本支持该选项，则禁用随机重启以提高实验可复现性
solverOpts = ik.SolverParameters;
if isfield(solverOpts,'AllowRandomRestart')
    solverOpts.AllowRandomRestart = false;
elseif isfield(solverOpts,'AllowRandomRestarts')
    solverOpts.AllowRandomRestarts = false;
end
ik.SolverParameters = solverOpts;

%% 3. 选定非零参考姿态，由正运动学得到一定可达的起始位姿
% 这六个角度是教学用数学测试值，不是已核实的机械工作范围
qReferenceDeg = [15; -25; 35; 10; 30; -15];
qReference = qReferenceDeg*pi/180;

TStart = getTransform(robot,qReference,'tool_flange');
pStart = TStart(1:3,4);
RStart = TStart(1:3,1:3);

% 第三课：位置沿短直线变化，法兰方向保持 RStart 不变
deltaPosition = [0.015; -0.010; 0.018];  % m，教学轨迹设计值
pEnd = pStart + deltaPosition;
TEnd = TStart;
TEnd(1:3,4) = pEnd;

fprintf('起点法兰坐标 (m)：\n'); disp(pStart.');
fprintf('目标终点坐标 (m)：\n'); disp(pEnd.');

%% 4. 先验证单个目标位姿能否逆解
[qEnd,infoEnd] = ik('tool_flange',TEnd,weights,qReference);
if ~strcmp(infoEnd.Status,'success')
    error('终点逆运动学未成功：%s（PoseErrorNorm=%.3e）。', ...
        infoEnd.Status,infoEnd.PoseErrorNorm);
end

TEndActual = getTransform(robot,qEnd,'tool_flange');
positionErrorEnd = norm(TEndActual(1:3,4)-pEnd);
RRelEnd = RStart.'*TEndActual(1:3,1:3);
cosAngleEnd = max(-1,min(1,(trace(RRelEnd)-1)/2));
orientationErrorEnd = acos(cosAngleEnd);

% 数值求解的教学验收阈值；不等于机械臂定位精度
maxPositionError = 1e-4;     % 0.1 mm
maxOrientationError = 1e-3;  % rad
assert(positionErrorEnd < maxPositionError, ...
    '终点位置误差超出本课预设的数值求解阈值。');
assert(orientationErrorEnd < maxOrientationError, ...
    '终点姿态误差超出本课预设的数值求解阈值。');

fprintf('终点逆解的六轴角度 (deg)：\n');
disp((qEnd(:)*180/pi).');
fprintf('终点正运动学回代：位置误差 %.6f mm，姿态误差 %.6f deg。\n', ...
    1000*positionErrorEnd,orientationErrorEnd*180/pi);

%% 5. 生成连续的笛卡尔直线轨迹
nPoints = 31;
uValues = linspace(0,1,nPoints);

targetXYZ = zeros(3,nPoints);
actualXYZ = zeros(3,nPoints);
qTrajectory = zeros(6,nPoints);
positionErrors = zeros(1,nPoints);
orientationErrors = zeros(1,nPoints);
statusHistory = cell(1,nPoints);

% 使用上一轨迹点的解作为下一点的初始猜测，帮助保持解分支连续
qPrevious = qReference;
maxJointStep = 0.15;  % rad/相邻路径点，仅为本课数值连续性检查

for i = 1:nPoints
    u = uValues(i);

    % 三次平滑插值：首末端沿归一化参数 u 的一阶导数为 0
    s = 3*u^2 - 2*u^3;

    % 位置轨迹是空间直线，目标姿态保持不变
    pDesired = pStart + s*deltaPosition;
    TDesired = TStart;
    TDesired(1:3,4) = pDesired;

    [qSolution,info] = ik('tool_flange',TDesired,weights,qPrevious);
    statusHistory{i} = info.Status;

    if ~strcmp(info.Status,'success')
        error('第 %d/%d 个轨迹点逆运动学失败：%s。', ...
            i,nPoints,info.Status);
    end
    qSolution = qSolution(:);

    if max(abs(qSolution-qPrevious)) >= maxJointStep
        error('第 %d 个点的关节角跳变超过本课数值连续性阈值。',i);
    end

    % 回代正运动学，独立评估目标与实际到达的位姿误差
    TActual = getTransform(robot,qSolution,'tool_flange');
    pActual = TActual(1:3,4);
    RActual = TActual(1:3,1:3);

    targetXYZ(:,i) = pDesired;
    actualXYZ(:,i) = pActual;
    qTrajectory(:,i) = qSolution;

    positionErrors(i) = norm(pActual-pDesired);

    RRelative = RStart.'*RActual;
    cosAngle = max(-1,min(1,(trace(RRelative)-1)/2));
    orientationErrors(i) = acos(cosAngle);

    assert(positionErrors(i) < maxPositionError, ...
        '轨迹点 %d 的位置误差超过阈值。',i);
    assert(orientationErrors(i) < maxOrientationError, ...
        '轨迹点 %d 的姿态误差超过阈值。',i);

    qPrevious = qSolution;
end

fprintf('\n%d 个目标位姿已求得逆解并回代检查。\n',nPoints);
fprintf('最大位置误差：%.6f mm\n',1000*max(positionErrors));
fprintf('最大姿态误差：%.6f deg\n',max(orientationErrors)*180/pi);
fprintf('相邻采样点最大关节变化：%.6f deg\n', ...
    max(max(abs(diff(qTrajectory,1,2))))*180/pi);

%% 6. 对比目标直线和逆运动学得到的实际轨迹
figure('Name','第三课：末端直线轨迹','Color','w');
plot3(targetXYZ(1,:),targetXYZ(2,:),targetXYZ(3,:), ...
    'k--','LineWidth',2);
hold on;
plot3(actualXYZ(1,:),actualXYZ(2,:),actualXYZ(3,:), ...
    'b-','LineWidth',1.6);
plot3(pStart(1),pStart(2),pStart(3),'go','MarkerFaceColor','g');
plot3(pEnd(1),pEnd(2),pEnd(3),'ro','MarkerFaceColor','r');
hold off;
grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
legend({'目标直线','逆解回代轨迹','起点','终点'},'Location','best');
title('末端法兰位置：期望值与正运动学回代值');
view(35,25);

%% 7. 绘制六关节角与位姿误差
figure('Name','第三课：六关节角度','Color','w');
plot(uValues,qTrajectory.'*180/pi,'LineWidth',1.3);
grid on;
xlabel('归一化轨迹参数 u（不是实际时间）');
ylabel('关节角度 (deg)');
title('沿目标直线移动所需的六轴关节角');
legend({'J1','J2','J3','J4','J5','J6'},'Location','best');

figure('Name','第三课：逆运动学数值误差','Color','w');
plot(uValues,positionErrors*1000,'LineWidth',1.3);
grid on;
xlabel('归一化轨迹参数 u');
ylabel('法兰位置误差 (mm)');
title('逆运动学位置误差（正运动学回代）');

%% 8. 动画：沿目标直线逐点移动
fig = figure('Name','第三课：末端直线移动动画','Color','w');
ax = axes('Parent',fig);
for i = 1:nPoints
    if ~ishandle(fig)
        error('动画窗口已关闭；请重新运行本课脚本。');
    end
    show(robot,qTrajectory(:,i),'Parent',ax, ...
        'Frames','off','Visuals','on','PreservePlot',false);
    axis(ax,[-1.05 1.05 -1.05 1.05 -0.15 1.25]);
    axis(ax,'equal');
    grid(ax,'on');
    view(ax,35,25);
    xlabel(ax,'X (m)'); ylabel(ax,'Y (m)'); zlabel(ax,'Z (m)');
    title(ax,sprintf('直线轨迹：%d/%d | 位置误差 %.4f mm', ...
        i,nPoints,1000*positionErrors(i)));
    drawnow;
    pause(0.04);  % 只控制显示速度，不是控制器采样周期
end

disp('第三课脚本结束：逆运动学和轨迹点回代检查通过。');
disp('注意：未执行碰撞检测、动力学、速度/加速度/力矩约束或闭环控制。');
