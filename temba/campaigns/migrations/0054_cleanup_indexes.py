# Generated by Django 4.2.3 on 2023-12-06 16:45

from django.db import migrations, models

SQL = """
DROP INDEX campaigns_eventfire_fired_not_null_idx;
DROP INDEX campaigns_eventfire_unfired_unique;
"""


class Migration(migrations.Migration):
    dependencies = [
        ("campaigns", "0053_base_to_und"),
        ("sql", "0005_squashed"),
    ]

    operations = [
        migrations.AddConstraint(
            model_name="eventfire",
            constraint=models.UniqueConstraint(
                condition=models.Q(("fired", None)), fields=("event_id", "contact_id"), name="eventfires_unfired_unique"
            ),
        ),
        migrations.RunSQL(SQL),
    ]