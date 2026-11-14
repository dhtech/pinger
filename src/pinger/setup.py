# setuptools: Python 3.12 and later have no distutils of their own.
# The version here is the release's: a tag vX.Y.Z must say the same
# (.github/workflows/release.yml).
from setuptools import setup, Extension

setup(name='dhmonpinger', version='0.2.0', ext_modules=[
    Extension('dhmonpinger', ['dhmonpinger.c'])])
