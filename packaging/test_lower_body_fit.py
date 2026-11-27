import unittest
from body_fit import AnatomySection
from garment_regions import Frame, Region, fit_regions

def section(y,width,front,back):
    return AnatomySection(y,0,0,width,front,back)

def region(src,dst,origin=(0,0,0)):
    x,y,z=origin
    frame=Frame.from_landmarks(origin,(x,y+1,z),(0,0,1))
    return Region(frame,frame,tuple(src),tuple(dst))

class LowerBodyFitTests(unittest.TestCase):
    def test_hips_glutes_waist(self):
        a=[section(0,.18,.10,.10),section(1,.14,.08,.08)]
        b=[section(0,.25,.10,.18),section(1,.12,.08,.08)]
        points=[(.20,0,0),(0,0,-.12),(0,0,.12),(.16,1,0)]
        result=fit_regions(points,[{"pelvis":1}]*4,{"pelvis":region(a,b)})
        for actual,expected in zip(result,[(.27,0,0),(0,0,-.20),(0,0,.12),(.14,1,0)]):
            for p,q in zip(actual,expected): self.assertAlmostEqual(p,q)
    def test_independent_leg_profiles(self):
        a=[section(0,.06,.06,.06),section(1,.10,.10,.10)]
        b=[section(0,.08,.06,.08),section(1,.15,.13,.14)]
        regions={"left":region(a,b,(-.2,0,0)),"right":region(a,a,(.2,0,0))}
        result=fit_regions([(-.08,1,0),(.32,1,0),(-.2,0,-.08)],
            [{"left":1},{"right":1},{"left":1}],regions)
        self.assertAlmostEqual(result[0][0],-.03)
        self.assertAlmostEqual(result[1][0],.32)
        self.assertAlmostEqual(result[2][2],-.10)
    def test_blend_at_shared_boundary(self):
        a=[section(0,.1,.1,.1),section(1,.1,.1,.1)]
        b=[section(0,.2,.1,.1),section(1,.2,.1,.1)]
        result=fit_regions([(.12,.5,0)],[{"a":1,"b":1}],{"a":region(a,a),"b":region(a,b)})
        self.assertAlmostEqual(result[0][0],.17)
