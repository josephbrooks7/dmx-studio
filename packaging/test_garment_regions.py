import unittest
from body_fit import Section
from garment_regions import Frame,Region,fit_regions

class RegionTests(unittest.TestCase):
    def setUp(self):
        self.a=Frame.from_landmarks((0,0,0),(0,1,0),(0,0,1))
        self.b=Frame.from_landmarks((0,0,0),(2,0,0),(0,0,1))
        self.s=(Section(0,0,0,1,1),Section(1,0,0,1,1))
        self.t=(Section(0,0,0,1,1),Section(2,0,0,1,1))
    def test_rotated_limb(self):
        r=Region(self.a,self.b,self.s,self.t)
        self.assertEqual(fit_regions([(0,.5,0)],[{"arm":1}],{"arm":r}),[(1.,0.,0.)])
    def test_blended_seam(self):
        r=Region(self.a,self.b,self.s,self.t)
        q=Region(self.a,self.a,self.s,self.s)
        self.assertEqual(fit_regions([(0,.5,0)],[{"arm":1,"torso":1}],{"arm":r,"torso":q}),[(.5,.25,0.)])
    def test_parallel_reference_rejected(self):
        with self.assertRaises(ValueError): Frame.from_landmarks((0,0,0),(0,1,0),(0,1,0))
    def test_missing_assignment(self):
        with self.assertRaises(ValueError): fit_regions([(0,0,0)],[],{})
    def test_negative_weight(self):
        with self.assertRaises(ValueError): fit_regions([(0,0,0)],[{"arm":-1}],{})
if __name__=="__main__": unittest.main()
