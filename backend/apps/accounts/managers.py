from django.contrib.auth.base_user import BaseUserManager


class UserManager(BaseUserManager):
    """Email or phone can identify an account; hashing stays Django's job."""

    use_in_migrations = True

    def _clean(self, ident: dict) -> dict:
        if ident.get("email"):
            ident["email"] = self.normalize_email(ident["email"]).lower()
        if ident.get("phone"):
            ident["phone"] = ident["phone"].strip()
        return ident

    def create_user(self, *, email=None, phone=None, password=None, **extra):
        if not email and not phone:
            raise ValueError("An account needs an email address or a phone number")
        extra = self._clean({"email": email, "phone": phone, **extra})
        user = self.model(email=extra.pop("email"), phone=extra.pop("phone"), **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, *, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("is_email_verified", True)
        extra.setdefault("verification_level", "operator")
        if not extra.get("full_name"):
            extra["full_name"] = "Operator"
        if not password:
            raise ValueError("A superuser needs a password")
        return self.create_user(email=email, password=password, **extra)
