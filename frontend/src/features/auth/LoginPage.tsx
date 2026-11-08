import { Button, Card } from "@heroui/react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { Database, LockKeyhole, ShieldCheck } from "lucide-react";
import { z } from "zod";
import { getCsrfToken, login } from "#/api/endpoints/auth/auth";
import { authKeys } from "#/api/query-keys";
import { ApiError } from "#/components/ui";
import { useAppForm } from "#/forms";

const route = getRouteApi("/login");

const schema = z.object({
	login: z.string().trim().min(1, "Enter your login"),
	password: z.string().min(1, "Enter your password"),
});

const DEMO_LOGINS = [
	{ login: "perf.manager.0001", role: "Manager - every client and project" },
	{ login: "perf.sales.0001", role: "Sales - own clients, team projects" },
	{ login: "perf.admin.0001", role: "Admin - users and teams" },
];

const FACTS = [
	{ icon: Database, text: "5 000 000 clients and projects, every call one T-SQL procedure" },
	{ icon: ShieldCheck, text: "The app login may only EXECUTE procedures of schema app" },
	{ icon: LockKeyhole, text: "Spring Security session, CSRF cookie, lockout after failed logins" },
];

export function LoginPage() {
	const search = route.useSearch();
	const navigate = useNavigate();
	const queryClient = useQueryClient();

	const mutation = useMutation({
		mutationFn: async (value: z.infer<typeof schema>) => {
			// The first write needs the XSRF-TOKEN cookie; this request sets it.
			await getCsrfToken();
			return login({ login: value.login, password: value.password });
		},
		onSuccess: (me) => {
			queryClient.setQueryData(authKeys.me(), me);
			void navigate({ to: search.redirect ?? "/" });
		},
	});

	const form = useAppForm({
		defaultValues: { login: "", password: "" },
		validators: { onChange: schema },
		onSubmit: ({ value }) => mutation.mutate(value),
	});

	return (
		<div className="grid min-h-screen lg:grid-cols-[1.05fr_1fr]">
			<section className="relative hidden overflow-hidden bg-sidebar px-14 py-12 text-sidebar-text lg:flex lg:flex-col">
				<div
					aria-hidden
					className="pointer-events-none absolute -top-40 -right-40 size-[520px] rounded-full border border-champagne/20"
				/>
				<div
					aria-hidden
					className="pointer-events-none absolute -top-24 -right-24 size-[360px] rounded-full border border-champagne/10"
				/>
				<div className="flex items-center gap-3">
					<img src="/favicon.svg" alt="" className="size-9" />
					<span className="font-mono text-[11px] tracking-[0.16em] text-sidebar-muted uppercase">
						crm.kotlin.db.app
					</span>
				</div>

				<div className="mt-auto max-w-lg">
					<p className="font-mono text-[11px] tracking-[0.16em] text-champagne uppercase">
						Clients · Projects · Teams
					</p>
					<h1 className="mt-4 font-display text-6xl leading-[1.05] font-semibold text-white">
						Every client,
						<br />
						every project,
						<br />
						<span className="text-champagne">one procedure away.</span>
					</h1>
					<ul className="mt-10 flex flex-col gap-4">
						{FACTS.map((fact) => (
							<li key={fact.text} className="flex items-start gap-3 text-sm">
								<fact.icon className="mt-0.5 size-4 shrink-0 text-champagne" strokeWidth={1.75} />
								<span>{fact.text}</span>
							</li>
						))}
					</ul>
				</div>

				<p className="mt-12 text-xs text-sidebar-muted">
					Kotlin · Spring Boot 4 · SQL Server 2025 Express · React · HeroUI
				</p>
			</section>

			<section className="flex items-center justify-center px-6 py-12">
				<div className="w-full max-w-sm">
					<div className="mb-8 lg:hidden">
						<img src="/favicon.svg" alt="" className="size-10" />
					</div>
					<h2 className="font-display text-4xl font-semibold">Sign in</h2>
					<p className="mt-2 text-sm text-muted">Use your CRM login and password.</p>

					<form
						noValidate
						className="mt-8 flex flex-col gap-5"
						onSubmit={(event) => {
							event.preventDefault();
							void form.handleSubmit();
						}}
					>
						<form.AppField name="login">
							{(field) => (
								<field.FormInput
									label="Login"
									autoComplete="username"
									placeholder="name.surname"
									autoFocus
								/>
							)}
						</form.AppField>
						<form.AppField name="password">
							{(field) => (
								<field.FormInput label="Password" type="password" autoComplete="current-password" />
							)}
						</form.AppField>
						<ApiError error={mutation.error} title="Sign-in failed" />
						<Button type="submit" fullWidth size="lg" isPending={mutation.isPending}>
							Sign in
						</Button>
					</form>

					<Card className="mt-10" variant="secondary">
						<Card.Header>
							<Card.Title className="font-mono text-[11px] tracking-[0.12em] uppercase">
								Seeded accounts
							</Card.Title>
							<Card.Description>
								Password: CRM_SEED_PASSWORD from infrastructure/.env
							</Card.Description>
						</Card.Header>
						<Card.Content className="flex flex-col gap-1">
							{DEMO_LOGINS.map((demo) => (
								<button
									key={demo.login}
									type="button"
									className="flex items-baseline justify-between gap-3 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-default"
									onClick={() => form.setFieldValue("login", demo.login)}
								>
									<span className="font-mono text-xs text-foreground">{demo.login}</span>
									<span className="text-[11px] text-muted">{demo.role}</span>
								</button>
							))}
						</Card.Content>
					</Card>
				</div>
			</section>
		</div>
	);
}
