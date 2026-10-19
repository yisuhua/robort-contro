"""PROPOSED headless Gazebo example; depends on a real ROS 2/GZ install."""
from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription, RegisterEventHandler, LogInfo
from launch.event_handlers import OnProcessExit
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import Command, FindExecutable, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    pkg = FindPackageShare('industrial_robot_integration')
    robot_xacro = PathJoinSubstitution([pkg, 'urdf', 'robot.urdf.xacro'])
    controller_yaml = PathJoinSubstitution([pkg, 'config', 'controllers.yaml'])
    world = PathJoinSubstitution([pkg, 'worlds', 'empty.sdf'])
    robot_description = ParameterValue(
        Command([
            FindExecutable(name='xacro'), ' ', robot_xacro, ' ',
            'demo_mode:=true ', 'controller_yaml:=', controller_yaml
        ]), value_type=str
    )
    rsp = Node(
        package='robot_state_publisher', executable='robot_state_publisher',
        name='robot_state_publisher', output='screen',
        parameters=[{'robot_description': robot_description, 'use_sim_time': True}]
    )
    gazebo = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([FindPackageShare('ros_gz_sim'), 'launch', 'gz_sim.launch.py'])
        ),
        launch_arguments={'gz_args': ['-r -s ', world]}.items()
    )
    # /clock only: joint state broadcaster owns /joint_states; TF is produced by RSP.
    clock_bridge = Node(
        package='ros_gz_bridge', executable='parameter_bridge', output='screen',
        arguments=['/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock'],
        remappings=[('/clock', '/clock')]
    )
    spawn = Node(
        package='ros_gz_sim', executable='create', output='screen',
        arguments=['-world', 'default', '-topic', 'robot_description',
                   '-name', 'industrial_robot_6r', '-allow_renaming', 'false']
    )
    jsb = Node(
        package='controller_manager', executable='spawner', output='screen',
        arguments=['joint_state_broadcaster', '--controller-manager',
                   '/controller_manager', '--controller-manager-timeout', '120']
    )
    jtc = Node(
        package='controller_manager', executable='spawner', output='screen',
        arguments=['joint_trajectory_controller', '--controller-manager',
                   '/controller_manager', '--controller-manager-timeout', '120']
    )
    return LaunchDescription([
        LogInfo(msg='PROPOSED demo dynamics only; no CAD or safety validation'),
        gazebo, clock_bridge, rsp, spawn,
        RegisterEventHandler(OnProcessExit(target_action=spawn, on_exit=[jsb])),
        RegisterEventHandler(OnProcessExit(target_action=jsb, on_exit=[jtc])),
    ])
