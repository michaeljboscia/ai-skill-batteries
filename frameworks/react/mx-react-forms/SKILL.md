---
name: mx-react-forms
description: React forms — React Hook Form, Zod validation, zodResolver, useForm, register, Controller, field arrays, multi-step wizards, FormProvider, useFormContext, controlled vs uncontrolled, useFormStatus, useFormState, server actions, form accessibility, aria-invalid, aria-describedby
---

# React Forms — Form Architecture for AI Coding Agents

**Load this skill when building forms, implementing validation, handling multi-step wizards, or deciding between controlled and uncontrolled input strategies.**

## When to also load
- `mx-react-state` — form state lives in RHF, NOT in Zustand or useState
- `mx-react-data` — mutations after form submission use TanStack Query
- `mx-react-testing` — form testing uses getByLabelText, getByRole, userEvent
- `mx-react-core` — Error Boundaries for form submission failures

---

## Level 1: Patterns That Always Work (Beginner)

### 1. React Hook Form + Zod — The Standard Stack

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

// 1. Define schema — single source of truth for validation AND types
const loginSchema = z.object({
  email: z.string().email('Invalid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

type LoginForm = z.infer<typeof loginSchema>; // TypeScript type derived from schema

// 2. Wire up the form
function LoginPage() {
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  });

  const onSubmit = async (data: LoginForm) => {
    await api.login(data); // data is fully typed and validated
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="email">Email</label>
        <input
          id="email"
          type="email"
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? 'email-error' : undefined}
          {...register('email')}
        />
        {errors.email && (
          <span id="email-error" role="alert">{errors.email.message}</span>
        )}
      </div>

      <div>
        <label htmlFor="password">Password</label>
        <input
          id="password"
          type="password"
          aria-invalid={!!errors.password}
          aria-describedby={errors.password ? 'password-error' : undefined}
          {...register('password')}
        />
        {errors.password && (
          <span id="password-error" role="alert">{errors.password.message}</span>
        )}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Logging in...' : 'Log In'}
      </button>
    </form>
  );
}
```

### 2. register for Native Inputs, Controller for Custom Components

```tsx
// Native HTML inputs — use register (uncontrolled, zero re-renders)
<input {...register('name')} />
<select {...register('country')}>
  <option value="us">United States</option>
</select>
<textarea {...register('bio')} />

// Custom UI library components (MUI, Radix, etc.) — use Controller
import { Controller } from 'react-hook-form';

<Controller
  name="category"
  control={control}
  render={({ field, fieldState: { error } }) => (
    <CustomSelect
      value={field.value}
      onChange={field.onChange}
      onBlur={field.onBlur}
      error={error?.message}
    />
  )}
/>
```

### 3. Accessibility Is Mandatory

Every form input MUST have:

| Requirement | Implementation |
|-------------|---------------|
| Visible label | `<label htmlFor="id">` linked to input |
| Error announcement | `role="alert"` on error message element |
| Invalid state | `aria-invalid={!!error}` on the input |
| Error association | `aria-describedby="error-id"` linking input to error |
| Required indicator | `aria-required="true"` or HTML `required` |
| Focus on error | Move focus to first invalid field after failed submit |

```tsx
// Focus first error after submission
const { setFocus } = useForm<FormData>();

const onInvalid = (errors: FieldErrors<FormData>) => {
  const firstError = Object.keys(errors)[0] as keyof FormData;
  setFocus(firstError);
};

<form onSubmit={handleSubmit(onSubmit, onInvalid)}>
```

### 4. defaultValue, Not value

```tsx
// BAD: Controlled — re-renders on every keystroke
<input value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})} />

// GOOD: Uncontrolled with default — zero re-renders during typing
const { register } = useForm({ defaultValues: { name: user.name } });
<input {...register('name')} />
```

---

## Level 2: Complex Form Patterns (Intermediate)

### Field Arrays for Dynamic Lists

```tsx
import { useFieldArray, useForm } from 'react-hook-form';

const schema = z.object({
  teammates: z.array(z.object({
    name: z.string().min(1, 'Required'),
    email: z.string().email(),
  })).min(1, 'At least one teammate'),
});

function TeamForm() {
  const { control, register, handleSubmit } = useForm({
    resolver: zodResolver(schema),
    defaultValues: { teammates: [{ name: '', email: '' }] },
  });

  const { fields, append, remove } = useFieldArray({ control, name: 'teammates' });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      {fields.map((field, index) => (
        <div key={field.id}> {/* Use field.id, NOT index */}
          <input {...register(`teammates.${index}.name`)} />
          <input {...register(`teammates.${index}.email`)} />
          <button type="button" onClick={() => remove(index)}>Remove</button>
        </div>
      ))}
      <button type="button" onClick={() => append({ name: '', email: '' })}>
        Add Teammate
      </button>
      <button type="submit">Save</button>
    </form>
  );
}
```

### Multi-Step Wizard with FormProvider

```tsx
const wizardSchema = z.object({
  // Step 1
  name: z.string().min(1),
  email: z.string().email(),
  // Step 2
  company: z.string().min(1),
  role: z.string().min(1),
  // Step 3
  plan: z.enum(['free', 'pro', 'enterprise']),
});

// Per-step schemas for progressive validation
const step1Schema = wizardSchema.pick({ name: true, email: true });
const step2Schema = wizardSchema.pick({ company: true, role: true });
const step3Schema = wizardSchema.pick({ plan: true });

function Wizard() {
  const [step, setStep] = useState(0);
  const methods = useForm({ resolver: zodResolver(wizardSchema), mode: 'onTouched' });
  const schemas = [step1Schema, step2Schema, step3Schema];

  const nextStep = async () => {
    const fields = Object.keys(schemas[step].shape) as Array<keyof typeof wizardSchema.shape>;
    const valid = await methods.trigger(fields); // Validate current step only
    if (valid) setStep(s => s + 1);
  };

  return (
    <FormProvider {...methods}>
      <form onSubmit={methods.handleSubmit(onFinalSubmit)}>
        {step === 0 && <Step1 />}
        {step === 1 && <Step2 />}
        {step === 2 && <Step3 />}
        
        {step > 0 && <button type="button" onClick={() => setStep(s => s - 1)}>Back</button>}
        {step < 2 ? (
          <button type="button" onClick={nextStep}>Next</button>
        ) : (
          <button type="submit">Submit</button>
        )}
      </form>
    </FormProvider>
  );
}

// Child steps access form via context — no prop drilling
function Step1() {
  const { register, formState: { errors } } = useFormContext();
  return (
    <>
      <input {...register('name')} />
      {errors.name && <span role="alert">{errors.name.message}</span>}
      <input {...register('email')} />
    </>
  );
}
```

### Cross-Field Validation with Zod

```tsx
const signupSchema = z.object({
  password: z.string().min(8),
  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'Passwords must match',
  path: ['confirmPassword'], // Error appears on confirmPassword field
});
```

### Validation Strategy Decision Tree

| Scenario | Mode | Why |
|----------|------|-----|
| Simple login/contact form | `onSubmit` (default) | Minimal re-renders, validate once |
| Complex form, real-time feedback needed | `onTouched` | Validates after field blur, then on change |
| Search/filter inputs | `onChange` | Immediate response expected |
| Multi-step wizard | `onTouched` + per-step `trigger()` | Validate step before advancing |

---

## Level 3: React 19 Form Primitives (Advanced)

### useFormStatus — Pending State Without Prop Drilling

```tsx
// Parent
<form action={serverAction}>
  <SubmitButton /> {/* No isSubmitting prop needed */}
</form>

// Child — reads form status from nearest <form> ancestor
import { useFormStatus } from 'react-dom';

function SubmitButton() {
  const { pending } = useFormStatus(); // Must be CHILD of <form>
  return (
    <button type="submit" disabled={pending}>
      {pending ? 'Saving...' : 'Save'}
    </button>
  );
}
```

### useActionState — Server-Side Validation

```tsx
import { useActionState } from 'react';

// Server action receives previous state + FormData
async function createUser(prevState: any, formData: FormData) {
  const data = Object.fromEntries(formData);
  const result = userSchema.safeParse(data);
  
  if (!result.success) {
    return { errors: result.error.flatten().fieldErrors };
  }
  
  await db.createUser(result.data);
  return { success: true };
}

function CreateUserForm() {
  const [state, formAction] = useActionState(createUser, { errors: {} });

  return (
    <form action={formAction}>
      <input name="email" />
      {state.errors?.email && <span role="alert">{state.errors.email[0]}</span>}
      <SubmitButton />
    </form>
  );
}
```

### Hybrid: Client Validation (RHF) + Server Validation (Actions)

RHF handles instant client-side feedback. Server action provides authoritative validation. Both use the same Zod schema.

---

## Performance: Make It Fast

### 1. Uncontrolled by Default
RHF's `register` attaches refs — DOM manages input state. Zero re-renders during typing. Only use `Controller` when the component API requires controlled props.

### 2. Minimize watch() Usage
`watch()` subscribes to field changes and triggers re-renders. Use sparingly. Prefer `getValues()` for on-demand reads or `useWatch` scoped to specific fields.

### 3. Unmount Unused Fields
Hidden fields still participate in validation and DOM. Unmount sections that aren't visible instead of `display: none`.

### 4. Lazy Mount Heavy Inputs
Rich text editors, file uploaders, date pickers — lazy load these with React.lazy + Suspense. Don't block initial form render for rarely-used inputs.

---

## Observability: Know It's Working

### 1. Form Submission Tracking

```tsx
const onSubmit = async (data: FormData) => {
  const start = performance.now();
  try {
    await api.submit(data);
    analytics.track('form_submitted', { form: 'signup', duration: performance.now() - start });
  } catch (err) {
    analytics.track('form_error', { form: 'signup', error: (err as Error).message });
    throw err;
  }
};
```

### 2. Validation Error Rate
Track which fields fail validation most often — indicates UX problems (confusing labels, unclear requirements).

### 3. Abandonment Detection
Track `beforeunload` or route changes with dirty forms to measure form abandonment rate.

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: No useState for Form Inputs
**You will be tempted to:** `const [email, setEmail] = useState('')` for every input.
**Why that fails:** N inputs × M keystrokes = N×M re-renders. A 20-field form with 50 characters each = 1,000 unnecessary re-renders. Users see input lag on low-end devices.
**The right way:** `useForm()` + `register()`. DOM manages input state. React only re-renders when validation state changes.

### Rule 2: No Skipping Accessibility
**You will be tempted to:** Use `placeholder` as the label. Change border color as the only error indicator.
**Why that fails:** Screen readers can't read placeholder text reliably. Color-only indicators fail for colorblind users. Missing `aria-invalid` means assistive technology doesn't announce errors.
**The right way:** `<label htmlFor>` + `aria-invalid` + `aria-describedby` + `role="alert"` on every error. If `getByLabelText` fails in tests, it's an a11y bug.

### Rule 3: No Global State for Form Data
**You will be tempted to:** Put form values in Zustand/Redux "so other components can read them."
**Why that fails:** Form state is ephemeral. Persisting it globally creates stale data after submission, complex cleanup logic, and tight coupling between form and store.
**The right way:** RHF owns form state. On successful submission, mutate server data (TanStack Query). Other components read from the server cache, not form state.

### Rule 4: No Index as Key in Field Arrays
**You will be tempted to:** `{fields.map((field, i) => <div key={i}>)}` because it compiles.
**Why that fails:** Reordering, inserting, or removing items causes React to mismatch DOM state with form state. User edits field A, removes field B, and field A's value jumps to field C.
**The right way:** `key={field.id}` — RHF generates stable unique IDs for each field array entry.

### Rule 5: No Validate-on-Every-Keystroke by Default
**You will be tempted to:** Set `mode: 'onChange'` on every form "for better UX."
**Why that fails:** Validation on every keystroke triggers re-renders, shows premature errors ("Invalid email" while still typing), and wastes CPU. Users see red errors before they finish typing.
**The right way:** `mode: 'onSubmit'` (default) or `mode: 'onTouched'` (validates after blur, then on change). Only `onChange` for search/filter inputs where immediate feedback is expected.
