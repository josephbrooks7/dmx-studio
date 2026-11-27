import unittest
from body_fit import AnatomySection, fit_anatomical_torso

def profile(front,back,width=.2):
    return [AnatomySection(y,0,0,width,front,back) for y in (0,1)]

class AnatomicalFitTests(unittest.TestCase):
    def test_front_projection_independent_of_back(self):
        a=profile(.10,.08); b=profile(.19,.08)
        result=fit_anatomical_torso([(0,.5,.12),(0,.5,-.10)],a,b)
        self.assertAlmostEqual(result[0][2],.21)
        self.assertAlmostEqual(result[1][2],-.10)
    def test_reverse_preserves_ease(self):
        self.assertAlmostEqual(fit_anatomical_torso([(0,.5,.23)],profile(.19,.08),profile(.10,.09))[0][2],.14)
    def test_shoulders_and_loose_fit(self):
        self.assertAlmostEqual(fit_anatomical_torso([(.25,.5,0)],profile(.1,.08),profile(.1,.08,.3))[0][0],.35)
    def test_no_body_mutation(self):
        a=profile(.1,.08); b=profile(.19,.08); before=tuple(b)
        fit_anatomical_torso([(0,.5,.12)],a,b)
        self.assertEqual(tuple(b),before)
    def test_invalid(self):
        with self.assertRaises(ValueError):
            fit_anatomical_torso([(0,.5,.12)],profile(.1,.08),profile(0,.08))
