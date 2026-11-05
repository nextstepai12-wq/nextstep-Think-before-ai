# THINK BEFORE AI — دليل التشغيل

## تجربة فورية (بدون Supabase)
افتح index.html في المتصفح: الواجهة والعدّاد وبطاقة المشارك تعمل بوضع تجريبي (الرقم 0001 والرمز DEMO01).

## التشغيل الكامل
1. أنشئ مشروعًا في supabase.com.
2. SQL Editor: الصق محتوى supabase.sql كاملًا ثم Run.
3. Authentication > Users > Add user: أنشئ بريد وكلمة مرور الإدارة. ثم Providers > Email: عطّل Allow new users to sign up.
4. Project Settings > API: انسخ Project URL و anon public key إلى config.js.
5. عدّل في config.js: EVENT (موعد اللقاء) و EVENT_TEXT و MEET (رابط Google Meet).
6. أنشئ مستودعًا على GitHub، ارفع محتويات المجلد (index.html و admin.html و config.js و assets/)، ثم Settings > Pages > Deploy from branch > main.
7. الإدارة: ضع /admin.html بعد رابط الموقع.

## ملاحظات
- لا ترفع supabase.sql إن أردت إبقاءه خاصًا، ولا تضع أبدًا مفتاح service_role في config.js.
- الأمان: كل الجداول مقفلة بـ RLS، والعامة تمر عبر دوال محددة. الإدارة فقط عبر Supabase Auth.
- الشهادة: تُمنح لمن سُجّل حضوره أو اعتُمد مخرجه (تسجيل الحضور من لوحة الإدارة).
