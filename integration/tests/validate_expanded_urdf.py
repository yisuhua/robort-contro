"""Contract check for ACTUALLY expanded Xacro output (no ROS 2 runtime needed)."""
import argparse
import math
from pathlib import Path
from xml.etree import ElementTree as ET

JOINTS = ['joint'+str(i) for i in range(1,7)]
AXES = [(0,0,1),(0,1,0),(0,1,0),(1,0,0),(0,1,0),(1,0,0)]
OFFSETS = [(0,0,0),(.080,0,.320),(.350,0,0),(.340,0,0),
           (0,0,0),(0,0,0)]


def floats(raw):
    return tuple(float(x) for x in raw.split())


def validate(path, mode):
    xml = ET.parse(path).getroot()
    assert xml.tag == 'robot'
    links = [x.attrib['name'] for x in xml.findall('link')]
    assert links == ['world','base_link']+['link'+str(i) for i in range(1,7)]+['tool_flange'], links
    joints = xml.findall('joint')
    selected = [next(x for x in joints if x.attrib['name']==name) for name in JOINTS]
    assert len(joints)==8, len(joints)
    for i,j in enumerate(selected):
        assert j.find('parent').attrib['link']==('base_link' if i==0 else 'link'+str(i))
        assert j.find('child').attrib['link']=='link'+str(i+1)
        assert floats(j.find('axis').attrib['xyz'])==AXES[i]
        assert all(math.isclose(a,b,abs_tol=1e-12)
                   for a,b in zip(floats(j.find('origin').attrib['xyz']), OFFSETS[i]))
        assert floats(j.find('origin').attrib['rpy'])==(0,0,0)
    assert selected[0].attrib['type']=='revolute'
    assert all(j.attrib['type']=='continuous' for j in selected[1:])
    assert math.isclose(float(selected[0].find('limit').attrib['upper']),math.radians(170),abs_tol=1e-12)
    assert math.isclose(float(selected[0].find('limit').attrib['lower']),-math.radians(170),abs_tol=1e-12)
    flange = next(x for x in joints if x.attrib['name']=='tool_fixed')
    assert floats(flange.find('origin').attrib['xyz'])==(.130,0,0)
    assert flange.find('parent').attrib['link']=='link6'
    control = xml.find('ros2_control')
    plugin = xml.find('./gazebo/plugin')
    inertials = sum(link.find('inertial') is not None for link in xml.findall('link'))
    if mode == 'demo':
        assert control is not None and plugin is not None
        controlled = [x.attrib['name'] for x in control.findall('joint')]
        assert controlled == JOINTS, controlled
        assert plugin.attrib['name']=='gz_ros2_control::GazeboSimROS2ControlPlugin'
        assert plugin.find('parameters') is not None
        assert inertials == 7, inertials
    else:
        assert control is None and plugin is None and inertials == 0
    print('PASS expanded xacro', mode, 'joints',len(joints),'inertials',inertials)


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('path',type=Path)
    p.add_argument('mode',choices=['kinematic','demo'])
    args=p.parse_args()
    validate(args.path,args.mode)
