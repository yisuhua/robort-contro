# P0 version and compatibility gate

Do not assume the installed ROS 2/Gazebo distribution from old screenshots or
by running an unrelated `ign` command. `gz_ros2_control` is for modern
Gazebo Sim, not Gazebo Classic. Its binary availability depends on the selected
ROS distro and Gazebo release.

## Required actual inventory

- ROS 2 distro and OS; Ubuntu version or other supported host.
- `ros2 pkg prefix ros_gz_sim`, `ros_gz_bridge`,
  `gz_ros2_control`, `controller_manager`, `xacro`.
- `gz sim --versions`, loaded plugin paths and DDS implementation.
- MATLAB release and ROS Toolbox / Robotics System Toolbox versions.
- controller topics, name mapping, simulation time and real package locations.

If any prerequisite is missing, P0 integration runtime is **BLOCKED**;
do not replace old code or auto-install packages. A user-authorized
compatible environment is needed before Gazebo is launched. Mathematical
CI can run independently and must not be interpreted as a physical
simulation PASS.

The GitHub-hosted **static CI** is intentionally only Python and Bash. It
does not claim remote access to MATLAB, SolidWorks, or the user machine.
