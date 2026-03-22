import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { classApi, type Class } from '../api/classApi';
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
import { Loader2 } from 'lucide-react';

const classSchema = z.object({
  name: z.string().min(1, 'Le nom est requis'),
  year: z.string().optional().or(z.literal('')),
});

type ClassForm = z.infer<typeof classSchema>;

interface UpdateClassDialogProps {
  cls: Class | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function UpdateClassDialog({ cls, open, onOpenChange }: UpdateClassDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset } = useForm<ClassForm>({
    resolver: zodResolver(classSchema),
  });

  useEffect(() => {
    if (cls && open) {
      reset({
        name: cls.name,
        year: cls.year || '',
      });
    }
  }, [cls, open, reset]);

  const updateMutation = useMutation({
    mutationFn: (data: ClassForm) => classApi.update(cls!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
      onOpenChange(false);
    },
    onError: (error: any) => {
      const detail = error.response?.data?.detail;
      if (Array.isArray(detail)) {
        setServerError(detail[0]?.msg || 'Erreur de validation');
      } else {
        setServerError(detail || 'Erreur lors de la modification');
      }
    }
  });

  const onSubmit = (data: ClassForm) => {
    setServerError(null);
    updateMutation.mutate(data);
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl">
        <DialogHeader>
          <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">Modifier la classe</DialogTitle>
          <DialogDescription className="text-slate-500">
            Modifiez le nom ou l'année scolaire de la classe.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5 pt-4">
          {serverError && (
            <div className="p-3 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm">
              {serverError}
            </div>
          )}
          
          <div className="space-y-2">
            <Label htmlFor="name_update" className="text-slate-700 font-medium">Nom de la classe</Label>
            <Input 
              id="name_update" 
              {...register('name')} 
              placeholder="ex: 6eme Primaire A"
              className={errors.name ? 'border-schooltrack-error bg-red-50/30' : 'border-slate-200 focus:border-schooltrack-primary'} 
            />
            {errors.name && <p className="text-schooltrack-error text-xs font-medium mt-1">{errors.name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="year_update" className="text-slate-700 font-medium">Année scolaire (optionnel)</Label>
            <Input 
              id="year_update" 
              {...register('year')} 
              placeholder="ex: 2025-2026"
              className={errors.year ? 'border-schooltrack-error bg-red-50/30' : 'border-slate-200 focus:border-schooltrack-primary'} 
            />
            {errors.year && <p className="text-schooltrack-error text-xs font-medium mt-1">{errors.year.message}</p>}
          </div>

          <DialogFooter className="gap-3 pt-4">
            <Button 
              type="button" 
              variant="outline" 
              onClick={() => onOpenChange(false)}
              className="rounded-xl h-11 border-slate-200"
            >
              Annuler
            </Button>
            <Button 
              type="submit" 
              disabled={updateMutation.isPending}
              className="rounded-xl h-11 bg-schooltrack-primary hover:bg-blue-900 text-white px-8 shadow-sm transition-all active:scale-95"
            >
              {updateMutation.isPending ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Modification...
                </>
              ) : 'Sauvegarder'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
