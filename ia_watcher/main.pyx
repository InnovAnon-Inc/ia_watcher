#! /usr/bin/env python
# cython: language_level=3
# distutils: language=c++

""" source watcher """

from contextlib          import contextmanager
from functools           import wraps
import importlib
import os
from pathlib             import Path
import subprocess
from typing              import Callable, List

from structlog           import get_logger
#from watchdog.events     import FileSystemEventHandler
from watchdog.events     import PatternMatchingEventHandler
from watchdog.events     import FileSystemEvent
from watchdog.events     import FileClosedNoWriteEvent
from watchdog.events     import FileOpenedEvent
from watchdog.observers  import Observer

from ia_clean.main       import main as clean_main
from ia_git.main         import main as git_main
from ia_pyinstaller.main import main as pyinstaller_main
from ia_setup.main       import main as setup_main

logger = get_logger()

class EventHandler(PatternMatchingEventHandler):

	def __init__(self:'EventHandler', observer:Observer,)->None:
		super().__init__(
			ignore_directories=True,
			ignore_patterns=[
				'.git/**',
				'.tox/**',
				'__pycache__/**',
				'build/**',
				'dist/**',
				'*.cpp',
				'*.spec',
				'*.egg-info/**',
			],
		)
		self.observer = observer

	def on_any_event(self:'EventHandler', event:FileSystemEvent)->None:
		src_path:Path = Path(event.src_path)

		if isinstance(event, FileClosedNoWriteEvent):
			#logger.debug('ignore: closing (%s)', event,)
			return
		if isinstance(event, FileOpenedEvent):
			#logger.debug('ignore: closing (%s)', event,)
			return

		build_dir:Path = Path('build') # TODO ignore this fucking shit
		if (build_dir in src_path.parents):
			#logger.debug('ignore build (%s)', src_path,)
			return

		git_dir:Path = Path('.git') # TODO ignore this fucking shit
		if (git_dir in src_path.parents):
			#logger.debug('ignore .git (%s)', src_path,)
			return

		logger.info('handling event: %s (%s)', src_path, event,)
		event_handler(observer=self.observer, src_path=src_path,)

def event_handler(observer:Observer, src_path:Path,)->None:
	_event_handler()

	deps:List[str] = ['ia_clean', 'ia_git', 'ia_pyinstaller', 'ia_setup', 'ia_watcher',]
	if (src_path.resolve().name not in deps):
		return
	assert (src_path.resolve().name in deps)
	logger.info('bootstrap required')
	observer.stop()

def _event_handler()->None:
	logger.info('before update')

	clean_main()
	git_main()
	setup_main()
	pyinstaller_main()

	logger.info('after update')

def loop(observer:Observer,)->None:
	while observer.is_alive():
		observer.join(1)

@contextmanager
def observe(observer:Observer,)->None:
	observer.start()
	yield
	observer.stop()
	observer.join()

import sys
def reexec()->None:
	os.execle(sys.argv[0], sys.argv, os.environ,)

#@pidfile()
def main()->None:
	path         :Path         = Path()
	logger.info('watching: %s', path.resolve(),)

	if bool(os.getenv('WATCHER_INIT', None)):
		logger.info('re-run')
	else:
		logger.info('first run')
		_event_handler()

	observer     :Observer     = Observer()
	event_handler:EventHandler = EventHandler(observer=observer,)
	observer.schedule(event_handler, path, recursive=True,)
	with observe(observer=observer,) as _:
		loop(observer=observer,)
	logger.info('terminating')
	os.environ['WATCHER_INIT'] = 'True'
	reexec()

__author__:str = 'you.com' # NOQA
