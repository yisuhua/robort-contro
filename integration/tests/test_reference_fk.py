"""Pure standard-library FK checks for documented Stage-1 math, not simulation."""
import math
import unittest

AXES = ((0, 0, 1), (0, 1, 0), (0, 1, 0), (1, 0, 0), (0, 1, 0), (1, 0, 0))
OFFSETS = ((0, 0, 0), (.080, 0, .320), (.350, 0, 0),
           (.340, 0, 0), (0, 0, 0), (0, 0, 0))


def mv(r, p):
    return [sum(r[i][k] * p[k] for k in range(3)) for i in range(3)]


def multiply(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rotation(axis, theta):
    x, y, z = axis
    c, s, t = math.cos(theta), math.sin(theta), 1-math.cos(theta)
    return [[t*x*x+c, t*x*y-s*z, t*x*z+s*y],
            [t*x*y+s*z, t*y*y+c, t*y*z-s*x],
            [t*x*z-s*y, t*y*z+s*x, t*z*z+c]]


def fk(q):
    r = [[1.,0.,0.],[0.,1.,0.],[0.,0.,1.]]
    p = [0.,0.,0.]
    for axis, offset, angle in zip(AXES, OFFSETS, q):
        d = mv(r,offset)
        p = [a+b for a,b in zip(p,d)]
        r = multiply(r,rotation(axis,angle))
    d = mv(r,(.130,0,0))
    p = [a+b for a,b in zip(p,d)]
    return p,r


class KinematicMath(unittest.TestCase):
    def assertVector(self, a, b):
        for x,y in zip(a,b):
            self.assertAlmostEqual(x,y,places=12)

    def test_home(self):
        self.assertVector(fk([0]*6)[0],[.900,0,.320])

    def test_j1_positive(self):
        self.assertVector(fk([math.pi/2,0,0,0,0,0])[0],[0,.900,.320])

    def test_j3_negative(self):
        self.assertVector(fk([0,0,-math.pi/2,0,0,0])[0],[.430,0,.790])

    def test_roll_changes_orientation_only(self):
        p0,r0 = fk([0]*6)
        p1,r1 = fk([0,0,0,math.pi/6,0,0])
        self.assertVector(p0,p1)
        self.assertNotEqual(r0,r1)


if __name__ == '__main__':
    unittest.main()
