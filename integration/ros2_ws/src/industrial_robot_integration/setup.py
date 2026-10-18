from setuptools import setup
from glob import glob
import os

package_name = 'industrial_robot_integration'
setup(
    name=package_name,
    version='0.1.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
        (os.path.join('share', package_name, 'urdf'), glob('urdf/*.xacro')),
        (os.path.join('share', package_name, 'config'), glob('config/*.yaml')),
        (os.path.join('share', package_name, 'worlds'), glob('worlds/*.sdf')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Project maintainer',
    maintainer_email='maintainer@example.invalid',
    description='PROPOSED 6R ROS 2 Gazebo integration',
    license='MIT',
    entry_points={'console_scripts': [
        'feedback_probe = industrial_robot_integration.feedback_probe:main',
    ]},
)
