import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { classApi } from '../api/classApi';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

const classSchema = z.object({
  name: z.string().min(1, 'Le nom est requis'),
  year: z.string().optional(),
});

type ClassForm = z.infer<typeof classSchema>;

interface CreateClassDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateClassDialog({ open, onOpenChange }: CreateClassDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset } = useForm<ClassForm>({
    resolver: zodResolver(classSchema),
    defaultValues: {
      name: '',
      year: '',
    }
  });

  const createMutation = useMutation({
    mutationFn: classApi.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
      reset();
      onOpenChange(false);
    },
    onError: (error: any) => {
      const detail = error.response?.data?.detail;
      if (Array.isArray(detail)) {
        setServerError(detail[0]?.msg || 'Erreur de validation');
      } else {
        setServerError(detail || 'Erreur lors de la création');
      }
    }
  });

  const onSubmit = (data: ClassForm) => {
    setServerError(null);
    createMutation.mutate({
      name: data.name,
      year: data.year || undefined,
    });
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      if (!val) reset();
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl">
        <DialogHeader>
          <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">Créer une classe</DialogTitle>
          <DialogDescription className="text-slate-500">
            Ajoutez une nouvelle classe à l'école.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 pt-4">
          {serverError && (
            <div className="p-3 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm">
              {serverError}
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="name">Nom de la classe</Label>
            <Input id="name" placeholder="Ex: 5ème A" {...register('name')} />
            {errors.name && <p className="text-red-500 text-xs">{errors.name.message}</p>}
          </div>
          <div className="space-y-2">
            <Label htmlFor="year">Année scolaire (optionnelle)</Label>
            <Input id="year" placeholder="Ex: 2025-2026" {...register('year')} />
            {errors.year && <p className="text-red-500 text-xs">{errors.year.message}</p>}
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Annuler
            </Button>
            <Button type="submit" disabled={createMutation.isPending}>
              {createMutation.isPending ? 'Création...' : 'Sauvegarder'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
