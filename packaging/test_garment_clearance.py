import unittest
from garment_clearance import SurfaceSample,correct_clearance

class ClearanceTests(unittest.TestCase):
    def setUp(self):
        self.s=[SurfaceSample((0,0,0),(0,0,2),"torso")]
    def test_penetration(self):
        p,bad=correct_clearance([(0,0,-.01)],["torso"],self.s)
        self.assertAlmostEqual(p[0][2],.005)
        self.assertEqual(bad,[])
    def test_already_clear(self):
        p,bad=correct_clearance([(0,0,.02)],["torso"],self.s)
        self.assertEqual(p,[(0,0,.02)])
        self.assertEqual(bad,[])
    def test_bounded_correction(self):
        p,bad=correct_clearance([(0,0,-.02)],["torso"],self.s,max_correction=.01)
        self.assertAlmostEqual(p[0][2],-.01)
        self.assertEqual(bad,[0])
    def test_region_isolation(self):
        p,bad=correct_clearance([(0,0,0)],["arm"],self.s)
        self.assertEqual(bad,[0])
    def test_out_of_range(self):
        p,bad=correct_clearance([(0,0,.2)],["torso"],self.s)
        self.assertEqual(bad,[0])
    def test_bad_normal(self):
        with self.assertRaises(ValueError):
            correct_clearance([],[],[SurfaceSample((0,0,0),(0,0,0),"torso")])
    def test_negative_limit(self):
        with self.assertRaises(ValueError):
            correct_clearance([],[],self.s,clearance=-1)
if __name__=="__main__": unittest.main()
