import { createFileRoute } from "@tanstack/react-router";
import { NewTicketPage } from "#/features/desk/NewTicketPage";

export const Route = createFileRoute("/_app/desk/new")({ component: NewTicketPage });
