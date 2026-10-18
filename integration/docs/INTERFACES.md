# Communications and ownership (PROPOSED)

| Channel | ROS 2 type | Publisher / source | Subscriber / consumer |
|---|---|---|---|
| `/clock` | `rosgraph_msgs/msg/Clock` | Gazebo Transport → **one** ros_gz_bridge | RSP / controllers |
| `/joint_states` | `sensor_msgs/msg/JointState` | **joint_state_broadcaster only** | RSP / MATLAB / probe |
| `/tf`, `/tf_static` | `tf2_msgs/msg/TFMessage` | robot_state_publisher | monitors, tools |
| `/joint_trajectory_controller/joint_trajectory` | `trajectory_msgs/msg/JointTrajectory` | MATLAB demo (or approved planner) | joint_trajectory_controller |
| `/joint_trajectory_controller/controller_state` | `control_msgs/msg/JointTrajectoryControllerState` | controller | future verifier |

**Do not bridge `/joint_states` in parallel with joint_state_broadcaster**:
it would create duplicate publishers and misleading feedback. The `/clock`
bridge is from Gazebo to ROS only. RSP computes TF from joint states; Gazebo
model visual state is not an independent kinematic ground truth.

`joint1`.. `joint6` are ordered six-axis names, units radians; model world
frame Z up; joint origin/axis transformations follow the pre-existing
MATLAB Stage-1 `build_robot.m` zero-fixed-rotation convention. Tool frame
is `tool_flange` and fixed +X 0.130 m from `link6`.

## Command timing and failure paths

- `JointTrajectoryPoint.time_from_start` is **relative** trajectory time;
  no ROS control-loop rate is implied by the sampled MATLAB teaching path.
- J1 demo amplitude 0.03 rad; J2–J6 stay at 0. A starting state not near
  demo home aborts the command. No hardware interface is implemented.
- Controller absent/inactive: do not publish. Feedback missing, wrong
  joint names, NaNs or incompatible timestamps: fail closed; record evidence.
- Simulation time must be nonzero, monotonically increasing for each run;
  a reset invalidates comparison and requires a fresh trial.
- ROS_DOMAIN_ID, middleware and host network interfaces must agree on the
  actual target setup. No firewall bypass or runtime network override assumed.
- Production integration would need authoritative collision meshes, actual
  joint limits, motor/gear limits, verified inertial properties, a controlled
  trajectory interface, contact/obstacle handling and independent stop logic.

## Python interface reserved, NOT ACTIVE

`python_adapter/contract_v1.schema.json` is only a future schema. There is no
ROS endpoint, plugin, or adapter execution to the independent direction-
generation Project. It must not import or overwrite that project's model,
data, parameters, results or Latest Valid.
