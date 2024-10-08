# Generated by Django 5.1 on 2024-10-02 20:51

import django.db.models.deletion
import django.db.models.functions.text
import django.utils.timezone
from django.conf import settings
from django.db import migrations, models

import temba.utils.fields
import temba.utils.uuid


class Migration(migrations.Migration):

    dependencies = [
        ("orgs", "0151_alter_usersettings_avatar"),
        ("tickets", "0063_remove_ticket_body"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="Shortcut",
            fields=[
                ("id", models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "is_active",
                    models.BooleanField(
                        default=True, help_text="Whether this item is active, use this instead of deleting"
                    ),
                ),
                (
                    "created_on",
                    models.DateTimeField(
                        blank=True,
                        default=django.utils.timezone.now,
                        editable=False,
                        help_text="When this item was originally created",
                    ),
                ),
                (
                    "modified_on",
                    models.DateTimeField(
                        blank=True,
                        default=django.utils.timezone.now,
                        editable=False,
                        help_text="When this item was last modified",
                    ),
                ),
                ("uuid", models.UUIDField(default=temba.utils.uuid.uuid4, unique=True)),
                ("name", models.CharField(max_length=64, validators=[temba.utils.fields.NameValidator(64)])),
                ("is_system", models.BooleanField(default=False)),
                ("text", models.TextField()),
                (
                    "created_by",
                    models.ForeignKey(
                        help_text="The user which originally created this item",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="%(app_label)s_%(class)s_creations",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "modified_by",
                    models.ForeignKey(
                        help_text="The user which last modified this item",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="%(app_label)s_%(class)s_modifications",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "org",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT, related_name="shortcuts", to="orgs.org"
                    ),
                ),
            ],
            options={
                "constraints": [
                    models.UniqueConstraint(
                        models.F("org"), django.db.models.functions.text.Lower("name"), name="unique_shortcut_names"
                    )
                ],
            },
        ),
    ]