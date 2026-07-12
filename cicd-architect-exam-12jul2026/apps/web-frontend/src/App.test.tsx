import React from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import App from "./App";

const mockTask = {
  id: "1",
  title: "Test Task",
  description: "A task for testing",
  status: "pending",
};

function mockFetchSequence(responses: Array<Partial<Response> & { json?: () => Promise<any> }>) {
  const fetchMock = jest.fn();
  responses.forEach((response) => {
    fetchMock.mockImplementationOnce(() =>
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => [],
        ...response,
      } as Response)
    );
  });
  global.fetch = fetchMock as unknown as typeof fetch;
  return fetchMock;
}

afterEach(() => {
  jest.resetAllMocks();
});

test("shows healthy status when API health check succeeds", async () => {
  mockFetchSequence([{ ok: true, json: async () => ({ status: "healthy" }) }, { ok: true, json: async () => [] }]);

  render(<App />);

  await waitFor(() => {
    expect(screen.getByTestId("health-indicator")).toHaveTextContent("healthy");
  });
});

test("shows unavailable status when API health check fails", async () => {
  const fetchMock = jest.fn().mockRejectedValue(new Error("network error"));
  global.fetch = fetchMock as unknown as typeof fetch;

  render(<App />);

  await waitFor(() => {
    expect(screen.getByTestId("health-indicator")).toHaveTextContent("unavailable");
  });
});

test("renders fetched tasks in the list", async () => {
  mockFetchSequence([
    { ok: true, json: async () => ({ status: "healthy" }) },
    { ok: true, json: async () => [mockTask] },
  ]);

  render(<App />);

  await waitFor(() => {
    expect(screen.getByText(/Test Task/)).toBeInTheDocument();
  });
});

test("submits a new task and refreshes the list", async () => {
  const fetchMock = mockFetchSequence([
    { ok: true, json: async () => ({ status: "healthy" }) },
    { ok: true, json: async () => [] },
    { ok: true, status: 201, json: async () => ({ ...mockTask, title: "New Task" }) },
    { ok: true, json: async () => [{ ...mockTask, title: "New Task" }] },
  ]);

  render(<App />);

  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

  await userEvent.type(screen.getByPlaceholderText("Title"), "New Task");
  await userEvent.type(screen.getByPlaceholderText("Description"), "New Description");
  await userEvent.click(screen.getByText("Add Task"));

  await waitFor(() => {
    expect(screen.getByText(/New Task/)).toBeInTheDocument();
  });
});
