import importlib
import json

from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Run one scheduled task in-process, so a missing worker never blocks the product."

    def add_arguments(self, parser):
        parser.add_argument("task")
        parser.add_argument("--payload", default="{}")

    def handle(self, *args, **options):
        dotted = options["task"]
        if "." not in dotted:
            raise CommandError("Give the task as module.function")
        module_path, function_name = dotted.rsplit(".", 1)
        module = importlib.import_module(module_path)
        function = getattr(module, function_name)
        payload = json.loads(options["payload"])
        result = function(**payload) if payload else function()
        self.stdout.write(json.dumps({"task": dotted, "result": result}))
