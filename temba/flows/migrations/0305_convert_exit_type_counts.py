# Generated by Django 4.0.7 on 2022-12-07 14:52

from django.db import migrations, transaction
from django.db.models import Sum

STATUS_ACTIVE = "A"
STATUS_WAITING = "W"
STATUS_COMPLETED = "C"
STATUS_INTERRUPTED = "I"
STATUS_EXPIRED = "X"
STATUS_FAILED = "F"

EXIT_TYPE_COMPLETED = "C"
EXIT_TYPE_INTERRUPTED = "I"
EXIT_TYPE_EXPIRED = "E"
EXIT_TYPE_FAILED = "F"

exit_type_to_status = {
    EXIT_TYPE_COMPLETED: STATUS_COMPLETED,
    EXIT_TYPE_INTERRUPTED: STATUS_INTERRUPTED,
    EXIT_TYPE_EXPIRED: STATUS_EXPIRED,
    EXIT_TYPE_FAILED: STATUS_FAILED,
}


def convert_exit_type_counts(apps, schema_editor):  # pragma: no cover
    Flow = apps.get_model("flows", "Flow")
    FlowRunStatusCount = apps.get_model("flows", "FlowRunStatusCount")

    num_flows = Flow.objects.filter(is_active=True).count()
    num_converted = 0

    for flow in Flow.objects.filter(is_active=True):
        with transaction.atomic():
            flow.status_counts.all().delete()

            status_counts = []

            def add_status_count(status: str, count: int):
                status_counts.append(FlowRunStatusCount(flow=flow, status=status, count=count, is_squashed=True))

            exit_type_totals = list(flow.exit_counts.values_list("exit_type").annotate(total=Sum("count")))
            for exit_type, count in exit_type_totals:
                if exit_type:
                    add_status_count(exit_type_to_status[exit_type], count)
                else:
                    if count > 0:
                        active_total = flow.runs.filter(status=STATUS_ACTIVE).count()
                        if active_total:
                            add_status_count(STATUS_ACTIVE, active_total)

                        waiting_total = flow.runs.filter(status=STATUS_WAITING).count()
                        if waiting_total:
                            add_status_count(STATUS_WAITING, waiting_total)

            FlowRunStatusCount.objects.bulk_create(status_counts)

        num_converted += 1
        if num_converted % 100 == 0:
            print(f"Converted counts for flow {num_converted}/{num_flows}")


def reverse(apps, schema_editor):  # pragma: no cover
    pass


def apply_manual():  # pragma: no cover
    from django.apps import apps

    convert_exit_type_counts(apps, None)


class Migration(migrations.Migration):

    dependencies = [
        ("flows", "0304_flowrunstatuscount_db_triggers"),
    ]

    operations = [migrations.RunPython(convert_exit_type_counts, reverse)]
