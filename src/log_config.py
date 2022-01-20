import os
from pathlib import Path
from dotenv import find_dotenv, load_dotenv


project_dir = Path(__file__).resolve().parents[1]
load_dotenv(find_dotenv())
LOGLEVEL = os.getenv("LOGLEVEL", "INFO").upper()
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "[%(asctime)s][%(levelname)-5s][%(name)s] - %(message)s",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
            "level": "INFO",
        },
        "rolling_file_debug": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": project_dir / "logs/debug.log",
            "formatter": "standard",
            "level": "DEBUG",
            "maxBytes": 1024 * 1024,
            "backupCount": 10,
        },
        "rolling_file_warning": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": project_dir / "logs/warnings.log",
            "formatter": "standard",
            "level": "WARNING",
            "maxBytes": 1024 * 1024,
            "backupCount": 10,
        },
    },
    "root": {
        "handlers": ["console", "rolling_file_debug", "rolling_file_warning"],
        "level": LOGLEVEL,
    },
    "loggers": {
        "__main__": {"handlers": [], "propagate": True},
        "src": {"handlers": [], "propagate": True},
    },
}
