import axios from "axios";
import { type Problem, problemMessage } from "#/api/mutator";
import type { I18n } from ".";

/*
 * Refusals of the procedures in the user's language (ADR-0008). The database throws a number and an English
 * message; the number picks the text here. A message with a name or a number in it is matched by a pattern and the
 * captured part (a person's name, a department) goes into the Polish text. A number this table does not know shows
 * the server's message as it is.
 */
type Text = { pl: string; en?: string; match?: RegExp; when?: RegExp };

/*
 * One number with several English messages (51050 of the seed, 51902) lists its texts; the first whose `when`
 * matches the message is used, a text without `when` matches any.
 */
const CRM: Record<number, Text | Text[]> = {
	// SQL Server's own errors the API passes on with the number (the detail is the title, e.g. "Already exists").
	547: { pl: "Nieprawidłowe odwołanie do innego wpisu." },
	1205: { pl: "Baza danych była zajęta. Spróbuj ponownie." },
	2601: { pl: "Taki wpis już istnieje (powtarza się login, NIP albo nazwa zespołu)." },
	2627: { pl: "Taki wpis już istnieje (powtarza się login, NIP albo nazwa zespołu)." },
	51010: { pl: "Nazwa klienta jest wymagana." },
	51011: { pl: "NIP musi mieć dokładnie 10 cyfr." },
	51012: { pl: "Adres e-mail jest nieprawidłowy." },
	51013: { pl: "Status musi być jednym z: LEAD, ACTIVE, INACTIVE." },
	51014: { pl: "Rozmiar strony musi być od 1 do 200." },
	51015: {
		pl: "Login musi mieć 3-64 znaki: litery, cyfry, kropka, podkreślenie albo łącznik.",
	},
	51016: { pl: "Rola musi być jedną z: ADMIN, MANAGER, SALES." },
	51017: { pl: "Klienta można przypisać tylko aktywnemu sprzedawcy." },
	51018: { pl: "Nie możesz zmienić własnej roli ani dezaktywować własnego konta." },
	51019: { pl: "Imię i nazwisko jest wymagane." },
	51020: { pl: "Hasło jest wymagane." },
	51030: { pl: "Nazwa projektu jest wymagana." },
	51031: { pl: "Etap musi być jednym z: NEW, ACCEPTED, ACTIVE, ON_HOLD, CLOSED, DECLINED." },
	51032: {
		pl: "Data rozpoczęcia i termin są wymagane, a termin nie może być przed datą rozpoczęcia.",
	},
	51033: { pl: "Budżet musi wynosić 0 lub więcej." },
	51034: { pl: "Treść komentarza jest wymagana." },
	51035: { pl: "Liderem zespołu może być tylko aktywny manager." },
	51036: { pl: "Nazwa zespołu jest wymagana." },
	51037: { pl: "Właścicielem projektu musi być aktywny członek zespołu projektu." },
	51038: { pl: "Do zespołu może dołączyć tylko aktywny użytkownik." },
	51050: [
		{ when: /clients must be 0/, pl: "Seed: liczba klientów musi wynosić 0 lub więcej." },
		{ when: /user counts/, pl: "Seed: liczby użytkowników muszą wynosić 0 lub więcej." },
		{
			when: /at most 9999 users/,
			pl: "Seed: najwyżej 9999 użytkowników na rolę (login perf.<rola>.NNNN).",
		},
		{
			when: /clients need/,
			pl: "Seed: klienci wymagają co najmniej jednego sprzedawcy, któremu zostaną przypisani.",
		},
		{
			when: /projects and comments/,
			pl: "Seed: liczby projektów i komentarzy muszą wynosić 0 lub więcej.",
		},
		{
			when: /projects need/,
			pl: "Seed: projekty wymagają klientów i co najmniej jednego managera (lidera zespołu).",
		},
		{ when: /comments need/, pl: "Seed: komentarze wymagają projektów." },
		{ when: /team size/, pl: "Seed: rozmiar zespołu musi wynosić 1 lub więcej." },
		{ when: /batch size/, pl: "Seed: rozmiar partii musi być od 1000 do 2000000." },
		{ when: /desk tickets/, pl: "Seed: liczba zgłoszeń musi być od 0 do 100000." },
	],
	51060: {
		pl: "Seed: baza ma już dane seeda albo klientów. Zacznij od pustej bazy (start.sh --clean).",
	},
	51301: { pl: "Nie masz uprawnień do tej operacji." },
	51302: { pl: "Twoje konto jest nieaktywne." },
	51303: { pl: "Sprzedawca może pracować tylko na klientach przypisanych do siebie." },
	51401: { pl: "Nie znaleziono klienta." },
	51402: { pl: "Nie znaleziono użytkownika." },
	51403: { pl: "Nie znaleziono projektu." },
	51404: { pl: "Nie znaleziono zespołu." },
	51901: [
		{
			when: /client/,
			pl: "Ktoś inny zmienił w międzyczasie tego klienta. Odśwież i spróbuj ponownie.",
		},
		{ pl: "Ktoś inny zmienił w międzyczasie ten projekt. Odśwież i spróbuj ponownie." },
	],
	51902: [
		{ when: /closed or declined/, pl: "Zamkniętego ani odrzuconego projektu nie można zmieniać." },
		{ pl: "Taka zmiana etapu jest niedozwolona." },
	],
	51904: {
		pl: "Klient ma projekty i nie można go usunąć. Zamiast tego ustaw status „Nieaktywny”.",
	},
	51905: {
		pl: "Ten użytkownik jest nadal właścicielem otwartych projektów zespołu. Najpierw przekaż je komuś innemu.",
	},
};

const DESK: Record<number, Text> = {
	// Offers (ADR-0013).
	51170: { pl: "Tytuł oferty jest wymagany (najwyżej 200 znaków)." },
	51171: { pl: "Wybierz szablon z listy." },
	51172: { pl: "Oferta musi być ważna od dziś do najwyżej roku." },
	51173: {
		pl: "Pozycja $1: opis (do 400 znaków), jednostka, ilość większa od 0, cena z najwyżej 2 miejscami po przecinku i VAT 0, 5, 8 lub 23%.",
		match: /Line (\d+)/,
	},
	51174: { pl: "Waluta musi być PLN, EUR albo USD." },
	51175: { pl: "Wstęp może mieć najwyżej 2000 znaków, a warunki 4000." },
	51176: { pl: "Oferta musi mieć co najmniej jedną pozycję, zanim zostanie wysłana." },
	51177: {
		pl: "Nieprawidłowe dane kontaktowe (stanowisko do 100 znaków, telefon 6-30 cyfr, poprawny e-mail).",
	},
	51178: { pl: "Nieprawidłowy filtr statusu." },
	51405: { pl: "Nie znaleziono oferty." },
	51906: { pl: "Tylko szkic oferty można edytować albo usunąć." },
	51907: { pl: "Ta zmiana statusu oferty nie jest dozwolona." },
	// Tasks (ADR-0014).
	51180: { pl: "Tytuł zadania jest wymagany (najwyżej 200 znaków)." },
	51181: {
		pl: "Nieprawidłowe daty: koniec nie może być przed początkiem, zadanie trwa najwyżej rok, a widok obejmuje najwyżej 120 dni.",
	},
	51182: { pl: "Nieprawidłowy zakres: tylko moje, mój dział albo wszystkie." },
	51183: { pl: "Nie ma takiego działu." },
	51184: { pl: "Opis zadania może mieć najwyżej 2000 znaków." },
	51304: { pl: "Sprzedawca zmienia tylko zadania, które założył albo które ma przypisane." },
	51406: { pl: "Nie znaleziono zadania." },
	// Sales pipeline (ADR-0015).
	51190: { pl: "Nazwa szansy jest wymagana (najwyżej 200 znaków)." },
	51191: { pl: "Wartość musi być liczbą 0 lub większą, z najwyżej 2 miejscami po przecinku." },
	51192: { pl: "Waluta musi być PLN, EUR albo USD." },
	51193: { pl: "Podaj przewidywaną datę zamknięcia." },
	51194: { pl: "Oferta musi należeć do tego samego klienta." },
	51195: { pl: "Nieprawidłowy filtr tablicy." },
	51196: { pl: "Wybierz etap lejka (nowa szansa zaczyna się w otwartym etapie)." },
	51197: { pl: "Podaj powód przegranej (najwyżej 400 znaków)." },
	51407: { pl: "Nie znaleziono szansy sprzedaży." },
	51100: { pl: "Pole „Tytuł” jest wymagane." },
	51101: { pl: "Pole „Tytuł” może mieć najwyżej 200 znaków." },
	51102: { pl: "Pole „Opis” jest wymagane." },
	51103: { pl: "Pole „Opis” może mieć najwyżej 4000 znaków." },
	51104: { pl: "Wybierz kategorię z listy." },
	51105: { pl: "Wybierz podkategorię należącą do wybranej kategorii." },
	51106: { pl: "Podkategoria „$1” nie przyjmuje już nowych zgłoszeń.", match: /"(.+)"/ },
	51107: { pl: "Wybierz priorytet." },
	51108: { pl: "Data zgłoszenia nie może być w przyszłości." },
	51109: { pl: "Data zgłoszenia może być najwyżej 30 dni wstecz." },
	51110: { pl: "Wybierz zgłaszającego z listy albo zaznacz „incognito”." },
	51111: { pl: "Pole „Powód” może mieć najwyżej 500 znaków." },
	51112: { pl: "Pole „Komentarz” jest wymagane." },
	51113: { pl: "Pole „Komentarz” może mieć najwyżej 2000 znaków." },
	51114: { pl: "Nie można przekazać zgłoszenia samemu sobie." },
	51115: { pl: "Wybierz osobę z działu $1.", match: /department (.+)\.$/ },
	51116: { pl: "Nieprawidłowy filtr listy." },
	51120: { pl: "Plik nie ma nazwy." },
	51121: {
		pl: "Plik „$1” ma niedozwolony typ. Dozwolone: obrazy (PNG, JPG, GIF, WEBP), PDF, dokumenty Office, TXT/CSV, ZIP, MP4/MOV.",
		match: /"(.+)"/,
	},
	51122: { pl: "Plik „$1” jest pusty.", match: /"(.+)"/ },
	51123: { pl: "Plik „$1” jest za duży. Limit to 20 MB.", match: /"(.+)"/ },
	51124: { pl: "Zgłoszenie może mieć najwyżej 10 załączników." },
	51130: { pl: "Pole „$1” nie należy do tej podkategorii.", match: /"(.+)"/ },
	51131: { pl: "Uzupełnij pole „$1”.", match: /"(.+)"/ },
	51132: { pl: "Pole „$1” może mieć najwyżej 200 znaków.", match: /"(.+)"/ },
	51133: { pl: "Pole „$1” musi być datą (rrrr-mm-dd).", match: /"(.+)"/ },
	51134: { pl: "Pole „$1” musi być adresem e-mail.", match: /"(.+)"/ },
	51135: {
		pl: "Pole „$1” musi być kwotą, np. 1 234,56 (najwyżej 2 miejsca po przecinku).",
		match: /"(.+)"/,
	},
	51136: { pl: "Pole „$1” nie jest poprawnym numerem rachunku (IBAN).", match: /"(.+)"/ },
	51137: { pl: "Pole „$1” musi być liczbą od 1 do 10000.", match: /"(.+)"/ },
	51138: { pl: "Wartości „$1” nie ma na liście tego pola.", match: /^"([^"]+)"/ },
	51139: { pl: "Wybierz wartość pola „$1” z listy.", match: /"(.+)"/ },
	51140: { pl: "Pole „$1” musi być numerem zgłoszenia, np. HAL-1A2B3C4D.", match: /"(.+)"/ },
	51141: { pl: "Wybierz rodzaj dokumentu, do którego należy numer." },
	51142: { pl: "Przy „Brak dokumentów” nie podaje się numeru dokumentu." },
	51143: { pl: "Podaj numer PESEL." },
	51144: { pl: "Numer PESEL jest niepoprawny (11 cyfr z poprawną cyfrą kontrolną)." },
	51145: { pl: "Podaj numer dowodu osobistego." },
	51146: { pl: "Ta podkategoria nie ma danych do raportu." },
	51150: { pl: "Wybierz okres najwyżej jednego roku (od <= do)." },
	51310: { pl: "Tylko agent realizujący zgłoszenie ($1) może je przekazać.", match: /\((.+)\)/ },
	51311: {
		pl: "Tylko agent realizujący zgłoszenie ($1) może je oddać do puli.",
		match: /\((.+)\)/,
	},
	51312: {
		pl: "Tylko agent realizujący zgłoszenie ($1) może je oznaczyć jako zrealizowane.",
		match: /\((.+)\)/,
	},
	51313: {
		pl: "Tylko agent realizujący zgłoszenie ($1) może wskazać osobę realizującą.",
		match: /\((.+)\)/,
	},
	51410: { pl: "Nie znaleziono zgłoszenia." },
	51411: { pl: "Nie znaleziono osoby." },
	51412: { pl: "Nie znaleziono agenta albo jego konto jest nieaktywne." },
	51413: { pl: "Nie znaleziono załącznika." },
	51910: {
		pl: "Ktoś był szybszy: zgłoszenie jest już w realizacji u: $1.",
		en: "Someone was faster: the ticket is already in progress with $1.",
		match: /with (.+)\.$/,
	},
	51911: { pl: "Zgłoszenie jest już zrealizowane." },
	51912: { pl: "Zgłoszenie jest w puli - najpierw trzeba je przejąć." },
	51913: { pl: "Ktoś był szybszy: zgłoszenie właśnie się zmieniło. Odśwież i spróbuj ponownie." },
};

/** The message of a failed request in the user's language. */
export function problemText(error: unknown, i18n: Pick<I18n, "lang" | "t" | "n">): string {
	if (axios.isAxiosError<Problem>(error)) {
		const data = error.response?.data;
		if (!error.response)
			return i18n.t(
				"Brak połączenia z serwerem. Sprawdź połączenie i spróbuj ponownie.",
				"The server cannot be reached. Check your connection and try again.",
			);
		// Two refusals of Spring, not of a procedure, so without a number: matched by their fixed text.
		if (data?.detail === "Invalid login or password.")
			return i18n.t("Nieprawidłowy login lub hasło.", "Invalid login or password.");
		if (data?.detail === "Current password is not correct.")
			return i18n.t("Obecne hasło jest nieprawidłowe.", "Current password is not correct.");
		if (error.response.status === 429)
			return i18n.t(
				"Zbyt wiele zgłoszeń w ostatniej minucie. Spróbuj za chwilę.",
				"Too many tickets were sent in the last minute. Try again shortly.",
			);
		const entry =
			data?.errorNumber != null ? (DESK[data.errorNumber] ?? CRM[data.errorNumber]) : undefined;
		const detail = data?.detail ?? "";
		const text = Array.isArray(entry)
			? entry.find((candidate) => !candidate.when || candidate.when.test(detail))
			: entry;
		if (text && data?.detail) {
			const captured = text.match?.exec(data.detail)?.[1] ?? "";
			// A captured catalog name (a field's label, a department) is Polish in the database: shown translated.
			if (i18n.lang === "en")
				return text.en
					? text.en.replace("$1", captured)
					: captured
						? data.detail.replace(captured, i18n.n(captured))
						: data.detail;
			return text.pl.replace("$1", i18n.n(captured) || captured);
		}
	}
	return problemMessage(error);
}
