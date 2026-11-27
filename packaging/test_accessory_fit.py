import unittest
from garment_regions import Frame
from garment_accessory_fit import fit_accessory

class AccessoryFitTests(unittest.TestCase):
    def setUp(self):
        self.a=Frame.from_landmarks((0,0,0),(0,1,0),(0,0,1))
        self.b=Frame.from_landmarks((1,2,3),(1,3,3),(0,0,1))
    def test_hat_independent_dimensions(self):
        self.assertEqual(fit_accessory([(1,1,1)],self.a,self.b,(1,1,1),(2,1,.5)),[(3,3,3.5)])
    def test_rigid_glasses(self):
        self.assertEqual(fit_accessory([(1,1,1)],self.a,self.b,(1,1,1),(2,2,2),adjustable_axes=(False,False,False)),[(2,3,4)])
    def test_hair_length_preserved(self):
        self.assertEqual(fit_accessory([(1,-1,0)],self.a,self.b,(1,1,1),(2,2,1),adjustable_axes=(True,False,True)),[(3,1,3)])
    def test_rotation(self):
        target=Frame.from_landmarks((0,0,0),(0,1,0),(1,0,0))
        self.assertEqual(fit_accessory([(0,0,1)],self.a,target,(1,1,1),(1,1,1)),[(1,0,0)])
    def test_size_limit(self):
        with self.assertRaises(ValueError):
            fit_accessory([(1,1,1)],self.a,self.b,(1,1,1),(3,1,1))
    def test_invalid_dimensions(self):
        with self.assertRaises(ValueError):
            fit_accessory([(1,1,1)],self.a,self.b,(0,1,1),(1,1,1))
    def test_input_unchanged(self):
        vertices=[(1,1,1)]
        fit_accessory(vertices,self.a,self.b,(1,1,1),(2,1,1))
        self.assertEqual(vertices,[(1,1,1)])
