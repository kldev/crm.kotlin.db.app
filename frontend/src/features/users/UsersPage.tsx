import { Button, Card, Chip, Dropdown, Label, Table, toast } from "@heroui/react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { getRouteApi } from "@tanstack/react-router";
import {
	Contact,
	EllipsisVertical,
	KeyRound,
	Plus,
	ShieldCheck,
	UserCheck,
	UserX,
} from "lucide-react";
import { useRef } from "react";
import type { UserResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import {
	ApiError,
	EmptyState,
	LoadMore,
	SelectFilter,
	TableSkeleton,
	UserAvatar,
} from "#/components/ui";
import { can, useMe } from "#/features/auth/session";
import { type ContactCommand, ContactDrawer } from "#/features/offers/ContactDrawer";
import { ROLES, type RoleName, roleColor, roleLabel } from "#/features/types";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import { formatRelative } from "#/lib";
import { usersQuery, useSetUserActive } from "./hooks";
import { UserDrawer, type UserDrawerCommand } from "./UserDrawer";

const route = getRouteApi("/_app/users");

export function UsersPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const query = useInfiniteQuery(usersQuery(search.role));
	const users = query.data?.pages.flatMap((p) => p.items) ?? [];
	const drawer = useRef<UserDrawerCommand>(null);
	const contactDrawer = useRef<ContactCommand>(null);
	const admin = can.manageUsers(me.role);
	const setActive = useSetUserActive((u) =>
		toast.success(
			u.active
				? t(`Konto ${u.displayName} jest aktywne`, `${u.displayName} is now active`)
				: t(`Konto ${u.displayName} jest nieaktywne`, `${u.displayName} is now inactive`),
		),
	);

	return (
		<>
			<PageHeader
				eyebrow={t("Administracja", "Administration")}
				title={t("Użytkownicy", "Users")}
				description={
					admin
						? t(
								"Zakładanie kont, zmiana ról, odblokowanie i dezaktywacja użytkowników.",
								"Create accounts, change roles, unlock and deactivate users.",
							)
						: t("Managerowie mają tylko podgląd.", "Read-only for managers.")
				}
				actions={
					admin ? (
						<Button onPress={() => drawer.current?.create()}>
							<Plus className="size-4" /> {t("Nowy użytkownik", "New user")}
						</Button>
					) : null
				}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex items-center gap-3 border-b border-separator p-4">
					<SelectFilter
						label={t("Rola", "Role")}
						value={search.role}
						options={ROLES.map((r) => ({ id: r, label: roleLabel(r, i18n) }))}
						onChange={(role) => void navigate({ search: { role: role as RoleName | undefined } })}
					/>
				</div>
				{query.isPending ? (
					<TableSkeleton />
				) : query.isError ? (
					<div className="p-4">
						<ApiError error={query.error} />
					</div>
				) : users.length === 0 ? (
					<EmptyState icon={ShieldCheck} title={t("Brak użytkowników", "No users")} />
				) : (
					<>
						<Table className="rounded-none shadow-none">
							<Table.ScrollContainer>
								<Table.Content aria-label={t("Użytkownicy", "Users")} className="min-w-[720px]">
									<Table.Header>
										<Table.Column isRowHeader>{t("Użytkownik", "User")}</Table.Column>
										<Table.Column>{t("Rola", "Role")}</Table.Column>
										<Table.Column>{t("Status", "Status")}</Table.Column>
										<Table.Column>{t("Ostatnie logowanie", "Last login")}</Table.Column>
										<Table.Column className="w-12">
											{admin ? <span className="sr-only">{t("Akcje", "Actions")}</span> : null}
										</Table.Column>
									</Table.Header>
									<Table.Body>
										{users.map((u) => (
											<Table.Row key={u.id} id={u.id}>
												<Table.Cell>
													<span className="flex items-center gap-3">
														<UserAvatar name={u.displayName} />
														<span className="flex flex-col leading-tight">
															<span className="font-medium">{u.displayName}</span>
															<span className="font-mono text-[11px] text-muted">{u.login}</span>
														</span>
													</span>
												</Table.Cell>
												<Table.Cell>
													<Chip
														size="sm"
														variant="soft"
														color={roleColor[u.role as RoleName] ?? "default"}
													>
														{roleLabel(u.role, i18n)}
													</Chip>
												</Table.Cell>
												<Table.Cell>
													<UserStatus user={u} />
												</Table.Cell>
												<Table.Cell>
													<span className="text-xs text-muted">
														{u.lastLoginAt
															? formatRelative(u.lastLoginAt, locale)
															: t("nigdy", "never")}
													</span>
												</Table.Cell>
												<Table.Cell>
													{admin && u.id !== me.id ? (
														<Dropdown>
															<Dropdown.Trigger>
																<Button
																	isIconOnly
																	size="sm"
																	variant="ghost"
																	aria-label={t(`Akcje: ${u.login}`, `Actions for ${u.login}`)}
																>
																	<EllipsisVertical className="size-4" />
																</Button>
															</Dropdown.Trigger>
															<Dropdown.Popover placement="bottom end">
																<Dropdown.Menu
																	onAction={(key) => {
																		if (key === "edit") drawer.current?.edit(u);
																		if (key === "contact") contactDrawer.current?.open(u.id);
																		if (key === "password") drawer.current?.resetPassword(u);
																		if (key === "toggle")
																			setActive.mutate(
																				{ id: u.id, active: !u.active },
																				{ onError: (e) => toast.danger(problemText(e, i18n)) },
																			);
																	}}
																>
																	<Dropdown.Item
																		id="edit"
																		textValue={t("Zmień rolę", "Change role")}
																	>
																		<ShieldCheck className="size-4" />
																		<Label>{t("Zmień rolę", "Change role")}</Label>
																	</Dropdown.Item>
																	<Dropdown.Item
																		id="contact"
																		textValue={t("Kontakt do ofert", "Contact for offers")}
																	>
																		<Contact className="size-4" />
																		<Label>{t("Kontakt do ofert", "Contact for offers")}</Label>
																	</Dropdown.Item>
																	<Dropdown.Item
																		id="password"
																		textValue={t("Ustaw hasło", "Set password")}
																	>
																		<KeyRound className="size-4" />
																		<Label>
																			{t("Ustaw hasło i odblokuj", "Set password and unlock")}
																		</Label>
																	</Dropdown.Item>
																	<Dropdown.Item
																		id="toggle"
																		textValue={
																			u.active
																				? t("Dezaktywuj", "Deactivate")
																				: t("Aktywuj", "Activate")
																		}
																		variant={u.active ? "danger" : "default"}
																	>
																		{u.active ? (
																			<UserX className="size-4" />
																		) : (
																			<UserCheck className="size-4" />
																		)}
																		<Label>
																			{u.active
																				? t("Dezaktywuj", "Deactivate")
																				: t("Aktywuj", "Activate")}
																		</Label>
																	</Dropdown.Item>
																</Dropdown.Menu>
															</Dropdown.Popover>
														</Dropdown>
													) : null}
												</Table.Cell>
											</Table.Row>
										))}
									</Table.Body>
								</Table.Content>
							</Table.ScrollContainer>
						</Table>
						<LoadMore
							noun={t("użytkowników", "users")}
							shown={users.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
						/>
					</>
				)}
			</Card>
			<UserDrawer ref={drawer} />
			<ContactDrawer ref={contactDrawer} />
		</>
	);
}

function UserStatus({ user }: { user: UserResponse }) {
	const { t } = useI18n();
	const locked = user.lockedUntil && new Date(`${user.lockedUntil}Z`).getTime() > Date.now();
	if (!user.active)
		return (
			<Chip size="sm" variant="soft">
				{t("Nieaktywny", "Inactive")}
			</Chip>
		);
	if (locked)
		return (
			<Chip size="sm" variant="soft" color="danger">
				{t("Zablokowany", "Locked")}
			</Chip>
		);
	return (
		<Chip size="sm" variant="soft" color="success">
			{t("Aktywny", "Active")}
		</Chip>
	);
}
