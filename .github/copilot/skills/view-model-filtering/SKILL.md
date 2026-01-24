---
name: ViewModel Filtering + Pagination
description: Build filterable/paginated list pages using embedded ViewModels and Scrivener.
---

## Scope

Use this skill for search/filter/list pages backed by query params.

## Checklist

- Add an embedded ViewModel in `lib/app/view_model/*` using `use App, :view_model`.
- Define `embedded_schema` fields for filters, and a `validate/1` function that returns `{ :ok, options, changeset }`.
- Build filtered queries using `scope/2` functions and `Repo.paginate/2` (Scrivener).
- In the LiveView, call `validate/1` in `handle_params/3`, assign `@form` via `to_form(changeset, as: "form")`.
- Use `push_patch` to keep filters in the URL and ensure invalid params raise `Web.Status.NotFound`.
