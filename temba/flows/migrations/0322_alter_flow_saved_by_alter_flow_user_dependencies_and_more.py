# Generated by Django 4.2.3 on 2023-10-05 18:24

import django.db.models.deletion
import django.utils.timezone
from django.conf import settings
from django.db import migrations, models

import temba.utils.models.fields


class Migration(migrations.Migration):
    dependencies = [
        ("orgs", "0129_remove_org_input_cleaners"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("flows", "0321_flow_optin_dependencies"),
    ]

    operations = [
        migrations.AlterField(
            model_name="flow",
            name="saved_by",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT, related_name="flow_saves", to="orgs.user"
            ),
        ),
        migrations.AlterField(
            model_name="flow",
            name="user_dependencies",
            field=models.ManyToManyField(related_name="dependent_flows", to="orgs.user"),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="created_by",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT, related_name="revisions", to="orgs.user"
            ),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="created_on",
            field=models.DateTimeField(default=django.utils.timezone.now),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="definition",
            field=temba.utils.models.fields.JSONAsTextField(default=dict),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="is_active",
            field=models.BooleanField(null=True),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="modified_by",
            field=models.ForeignKey(
                null=True, on_delete=django.db.models.deletion.PROTECT, to=settings.AUTH_USER_MODEL
            ),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="modified_on",
            field=models.DateTimeField(null=True),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="revision",
            field=models.IntegerField(),
        ),
        migrations.AlterField(
            model_name="flowrevision",
            name="spec_version",
            field=models.CharField(default="11.12", max_length=8),
        ),
    ]