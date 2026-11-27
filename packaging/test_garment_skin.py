import unittest
from garment_skin import transfer_weights

class SkinTests(unittest.TestCase):
    def fit(self,vertices,**kwargs):
        return transfer_weights(vertices,[(0,0,0),(.02,0,0)],
            [{"old_arm":1},{"torso":1}],{"old_arm":"arm"},{"arm","torso"},**kwargs)
    def test_exact(self):
        self.assertEqual(self.fit([(0,0,0)]),[{"arm":1}])
    def test_blend(self):
        self.assertEqual(self.fit([(.01,0,0)]),[{"arm":.5,"torso":.5}])
    def test_limit(self):
        self.assertEqual(self.fit([(.01,0,0)],max_influences=1),[{"arm":1}])
    def test_distance(self):
        with self.assertRaises(ValueError): self.fit([(1,0,0)])
    def test_unmapped(self):
        with self.assertRaises(ValueError):
            transfer_weights([(0,0,0)],[(0,0,0)],[{"bad":1}],{},{"arm"})
    def test_empty_sample(self):
        with self.assertRaises(ValueError):
            transfer_weights([(0,0,0)],[(0,0,0)],[{}],{},{"arm"})
if __name__=="__main__": unittest.main()
