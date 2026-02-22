# Hook & Dialog Patterns Reference

## useXxxData (Data Fetch + State)

```typescript
export function useXxxData(id: string) {
  const [data, setData] = useState<Data | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const fetchData = useCallback(async () => {
    setIsLoading(true);
    const res = await fetch(`/api/xxx/${id}`);
    setData(await res.json());
    setIsLoading(false);
  }, [id]);

  useEffect(() => { fetchData(); }, [fetchData]);

  return { data, isLoading, fetchData, setData };
}
```

## useXxxActions (CRUD)

```typescript
export function useXxxActions({ id, onRefresh }: { id: string; onRefresh: () => Promise<void> }) {
  const create = useCallback(async (data: CreateData) => {
    await fetch(`/api/xxx/${id}`, { method: "POST", body: JSON.stringify(data) });
    await onRefresh();
  }, [id, onRefresh]);

  return { create, update, delete: remove };
}
```

## Dialog Component

```typescript
interface DialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: Item | null;
  onConfirm: (data: FormData) => Promise<void>;
}

export function EditDialog({ open, onOpenChange, item, onConfirm }: DialogProps) {
  const [form, setForm] = useState<FormData>(getInitial(item));

  useEffect(() => {
    if (open && item) setForm(getInitial(item));
  }, [open, item]);

  const handleSubmit = async () => {
    await onConfirm(form);
    onOpenChange(false);
  };

  return <Dialog open={open} onOpenChange={onOpenChange}>...</Dialog>;
}
```
