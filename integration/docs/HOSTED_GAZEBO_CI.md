# GitHub-hosted ROS 2/Gazebo trial (NOT production validation)

`.github/workflows/robot-integration-gazebo-hosted.yml` provisions a temporary
GitHub Actions Linux container with ROS 2 Jazzy and compatible packaged Gazebo
components. It never executes on the user's Windows or ROS 2 environment.

Gates: dependency installation → colcon build → Xacro expansion →
headless `gz sim` launch → both controllers ACTIVE → /joint_states timestamp/
name checks → small J1 +0.03 rad command → observed feedback.

If it passes, claim only a **hosted DEMO roundtrip**, not target-platform
compatibility, physical robot accuracy, MATLAB communication, CAD collision,
actuator sizing, true dynamics, or safety. All plugin and simulator errors must
be saved and diagnosed. This job may be blocked by container images, APT
network/availability or ROS/Gazebo version differences.

The separate MATLAB ROS 2 demo remains an independent NOT RUN gate.
