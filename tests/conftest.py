"""Tests never touch the real ~/.config/living-sky or ~/.cache/living-sky: both point at a temp dir before
any project module is imported."""
import os
import sys
import tempfile

_tmp = tempfile.mkdtemp(prefix='living-sky-tests-')
os.environ['XDG_CONFIG_HOME'] = os.path.join(_tmp, 'config')
os.environ['XDG_CACHE_HOME'] = os.path.join(_tmp, 'cache')
os.makedirs(os.environ['XDG_CONFIG_HOME'], exist_ok=True)
os.makedirs(os.environ['XDG_CACHE_HOME'], exist_ok=True)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.join(ROOT, 'core'))
