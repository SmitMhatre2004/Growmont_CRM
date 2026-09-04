import { useState, useEffect } from 'react';
import { CheckCircle2, Circle, Trash2, Plus } from 'lucide-react';

interface Todo {
  id: string;
  text: string;
  done: boolean;
  createdAt: string;
}

export default function TodoWidget({ userId }: { userId: string | number }) {
  const storageKey = `todos_${userId}`;
  const [todos, setTodos] = useState<Todo[]>([]);
  const [input, setInput] = useState('');

  // Load from localStorage on mount
  useEffect(() => {
    const saved = localStorage.getItem(storageKey);
    if (saved) setTodos(JSON.parse(saved));
  }, [storageKey]);

  // Save to localStorage on change
  useEffect(() => {
    localStorage.setItem(storageKey, JSON.stringify(todos));
  }, [todos, storageKey]);

  const addTodo = () => {
    if (!input.trim()) return;
    setTodos([
      {
        id: Date.now().toString(),
        text: input.trim(),
        done: false,
        createdAt: new Date().toLocaleDateString(),
      },
      ...todos,
    ]);
    setInput('');
  };

  const toggleTodo = (id: string) => {
    setTodos(todos.map(t => t.id === id ? { ...t, done: !t.done } : t));
  };

  const deleteTodo = (id: string) => {
    setTodos(todos.filter(t => t.id !== id));
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') addTodo();
  };

  const pending = todos.filter(t => !t.done).length;

  return (
    <div className="bg-white rounded-2xl border border-gray-200 p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <CheckCircle2 color="#00337C" size={20} />
          <h2 className="text-xl font-semibold text-gray-900">To-Do</h2>
        </div>
        {pending > 0 && (
          <span className="text-xs bg-blue-100 text-blue-700 font-medium px-2 py-1 rounded-full">
            {pending} pending
          </span>
        )}
      </div>

      {/* Input */}
      <div className="flex gap-2 mb-4">
        <input
          type="text"
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Add a new task..."
          className="flex-1 text-sm border border-gray-200 rounded-lg px-3 py-2 outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
        />
        <button
          onClick={addTodo}
          className="bg-[#00337C] hover:bg-blue-900 text-white rounded-lg px-3 py-2 transition"
        >
          <Plus size={18} />
        </button>
      </div>

      {/* Todo List */}
      {todos.length === 0 ? (
        <div className="text-center py-8">
          <CheckCircle2 className="mx-auto text-gray-300 mb-2" size={36} />
          <p className="text-sm text-gray-400">No tasks yet. Add one above!</p>
        </div>
      ) : (
        <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
          {todos.map(todo => (
            <div
              key={todo.id}
              className={`flex items-center gap-3 p-3 rounded-lg border transition ${
                todo.done
                  ? 'bg-gray-50 border-gray-100'
                  : 'bg-white border-gray-200'
              }`}
            >
              {/* Toggle */}
              <button onClick={() => toggleTodo(todo.id)} className="shrink-0">
                {todo.done ? (
                  <CheckCircle2 size={18} className="text-green-500" />
                ) : (
                  <Circle size={18} className="text-gray-300" />
                )}
              </button>

              {/* Text */}
              <span
                className={`flex-1 text-sm ${
                  todo.done ? 'line-through text-gray-400' : 'text-gray-700'
                }`}
              >
                {todo.text}
              </span>

              {/* Delete */}
              <button
                onClick={() => deleteTodo(todo.id)}
                className="shrink-0 text-gray-300 hover:text-red-400 transition"
              >
                <Trash2 size={15} />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Footer */}
      {todos.some(t => t.done) && (
        <button
          onClick={() => setTodos(todos.filter(t => !t.done))}
          className="mt-3 text-xs text-gray-400 hover:text-red-400 transition"
        >
          Clear completed
        </button>
      )}
    </div>
  );
}