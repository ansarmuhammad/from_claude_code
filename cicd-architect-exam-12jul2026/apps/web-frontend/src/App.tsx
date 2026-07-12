import React, { useCallback, useEffect, useState } from "react";

const API_URL = process.env.REACT_APP_API_URL || "http://localhost:8000";

interface Task {
  id?: string;
  title: string;
  description: string;
  status: string;
  created_at?: string;
  updated_at?: string;
}

function App() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [healthy, setHealthy] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);

  const checkHealth = useCallback(async () => {
    try {
      const response = await fetch(`${API_URL}/health`);
      setHealthy(response.ok);
    } catch {
      setHealthy(false);
    }
  }, []);

  const fetchTasks = useCallback(async () => {
    try {
      const response = await fetch(`${API_URL}/api/v1/tasks`);
      if (!response.ok) {
        throw new Error(`Failed to fetch tasks: ${response.status}`);
      }
      const data = await response.json();
      setTasks(data);
      setError(null);
    } catch (err) {
      setError((err as Error).message);
    }
  }, []);

  useEffect(() => {
    checkHealth();
    fetchTasks();
  }, [checkHealth, fetchTasks]);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!title.trim() || !description.trim()) {
      return;
    }
    try {
      const response = await fetch(`${API_URL}/api/v1/tasks`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, description, status: "pending" }),
      });
      if (!response.ok) {
        throw new Error(`Failed to create task: ${response.status}`);
      }
      setTitle("");
      setDescription("");
      await fetchTasks();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="App">
      <header>
        <h1>Task Manager</h1>
        <p data-testid="health-indicator">
          API status:{" "}
          <span
            style={{ color: healthy ? "green" : "red" }}
          >
            {healthy === null ? "checking..." : healthy ? "healthy" : "unavailable"}
          </span>
        </p>
      </header>

      <form onSubmit={handleSubmit}>
        <input
          type="text"
          placeholder="Title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <input
          type="text"
          placeholder="Description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />
        <button type="submit">Add Task</button>
      </form>

      {error && <p role="alert">{error}</p>}

      <ul>
        {tasks.map((task) => (
          <li key={task.id}>
            <strong>{task.title}</strong> - {task.description} ({task.status})
          </li>
        ))}
      </ul>
    </div>
  );
}

export default App;
