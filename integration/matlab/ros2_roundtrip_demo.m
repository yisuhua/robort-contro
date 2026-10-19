function result = ros2_roundtrip_demo(repoRoot)
% Read existing Stage-1 MATLAB model, send SMALL DEMO-only trajectory to Gazebo.
% Requires ROS Toolbox, Robotics System Toolbox, ROS2/Gazebo demo active.
% NOT a safety-rated controller or a physical robot interface.
if nargin ~= 1 || ~isfolder(repoRoot)
    error('Provide local repository root containing matlab/robot_model/build_robot.m.');
end
modelScript = fullfile(repoRoot,'matlab','robot_model','build_robot.m');
assert(isfile(modelScript),'Existing Stage-1 model script not found.');
run(modelScript);  % Original script creates robot; does not edit source.
assert(isa(robot,'rigidBodyTree') && strcmp(robot.DataFormat,'column'));
names = {'joint1','joint2','joint3','joint4','joint5','joint6'};
assert(robot.NumBodies == 7 && isequal(size(homeConfiguration(robot)),[6 1]));
T0 = getTransform(robot,zeros(6,1),'tool_flange');
assert(norm(T0(1:3,4)-[.900;0;.320]) < 1e-10, ...
    'Stage-1 model changed; refusing to publish.');

node = ros2node('/industrial_robot_matlab_demo');
stateSub = ros2subscriber(node,'/joint_states','sensor_msgs/JointState');
pub = ros2publisher(node,'/joint_trajectory_controller/joint_trajectory', ...
    'trajectory_msgs/JointTrajectory');

% Require working feedback and ordered names BEFORE publishing anything.
initial = receive(stateSub,15);
[initialQ,initialNames] = mapJointState(initial,names);
assert(isequal(initialNames,names),'Unexpected joint-name mapping.');
assert(all(abs(initialQ) < 0.08), ...
    'Robot is not at approximate demo home; refusing to command motion.');

% Only J1 motion; ±170° is the sole CONFIRMED joint limit.
% 0.03 rad is a PROPOSED communication smoke-test amplitude.
target = zeros(6,1);
target(1) = 0.03;
traj = ros2message(pub);
traj.joint_names = names;
point = ros2message('trajectory_msgs/JointTrajectoryPoint');
point.positions = target(:).';
point.time_from_start = ros2duration(4);
traj.points = point;
send(pub,traj);

maxJointError = 0.01; % PROPOSED demo diagnostic, not precision requirement
maxWaitSeconds = 15;
tic;
finalQ = initialQ;
reached = false;
while toc < maxWaitSeconds
    [sample,received] = receive(stateSub,2);
    if ~received
        continue
    end
    [finalQ,~] = mapJointState(sample,names);
    if norm(finalQ-target,inf) < maxJointError
        reached = true;
        break
    end
end
assert(reached,'No confirmed motion feedback within diagnostic timeout.');
TMeasured = getTransform(robot,finalQ,'tool_flange');
TTarget = getTransform(robot,target,'tool_flange');
result = struct('status','DEMO_ROUNDTRIP_OBSERVED', ...
    'jointErrorInfRad',norm(finalQ-target,inf), ...
    'positionDifferenceM',norm(TMeasured(1:3,4)-TTarget(1:3,4)), ...
    'feedbackQ',finalQ,'targetQ',target);
disp(result);
% Does not claim continuous tracking, collision safety, or MATLAB/Gazebo FK parity.
end

function [q,namesOut] = mapJointState(msg,requiredNames)
allNames = cellstr(string(msg.name));
assert(numel(unique(allNames))==numel(allNames),'Duplicate joint names.');
assert(numel(msg.position)==numel(allNames),'Invalid JointState dimensions.');
q = zeros(6,1);
for i=1:6
    idx = find(strcmp(allNames,requiredNames{i}));
    assert(numel(idx)==1,'Missing or duplicate required joint.');
    q(i) = double(msg.position(idx));
end
assert(all(isfinite(q)),'Non-finite joint angles.');
namesOut = requiredNames;
end
