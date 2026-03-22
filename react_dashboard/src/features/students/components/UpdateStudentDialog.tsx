import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { studentApi, type Student } from '../api/studentApi';
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

const studentSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  email: z.string().email('Email invalide').optional().or(z.literal('')),
});

type StudentForm = z.infer<typeof studentSchema>;

interface UpdateStudentDialogProps {
  student: Student | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function UpdateStudentDialog({ student, open, onOpenChange }: UpdateStudentDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset } = useForm<StudentForm>({
    resolver: zodResolver(studentSchema),
  });

  useEffect(() => {
    if (student && open) {
      reset({
        first_name: student.first_name,
        last_name: student.last_name,
        email: student.email || '',
      });
    }
  }, [student, open, reset]);

  const updateMutation = useMutation({
    mutationFn: (data: StudentForm) => studentApi.update(student!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      onOpenChange(false);
    },
    onError: (error: any) => {
      setServerError(error.response?.data?.detail || 'Erreur lors de la modification');
    }
  });

  const onSubmit = (data: StudentForm) => {
    setServerError(null);
    updateMutation.mutate({
      first_name: data.first_name,
      last_name: data.last_name,
      email: data.email || undefined,
    });
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl">
        <DialogHeader>
          <DialogTitle className="text-2xl font-bold text-slate-900">Modifier l'élève</DialogTitle>
          <DialogDescription className="text-slate-500">
            Modifiez les informations de l'élève.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5 pt-4">
          {serverError && (
            <div className="p-3 bg-red-50 text-red-700 border border-red-100 rounded-xl text-sm animate-in fade-in zoom-in duration-200">
              {serverError}
            </div>
          )}
          
          <div className="space-y-2">
            <Label htmlFor="last_name_update" className="text-slate-700 font-medium">Nom</Label>
            <Input 
              id="last_name_update" 
              {...register('last_name')} 
              placeholder="ex: Dupont"
              className={errors.last_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} 
            />
            {errors.last_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.last_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="first_name_update" className="text-slate-700 font-medium">Prénom</Label>
            <Input 
              id="first_name_update" 
              {...register('first_name')} 
              placeholder="ex: Jean"
              className={errors.first_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} 
            />
            {errors.first_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.first_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="email_update" className="text-slate-700 font-medium">Email (optionnel)</Label>
            <Input 
              id="email_update" 
              type="email" 
              placeholder="eleve@ecole.be" 
              {...register('email')} 
              className={errors.email ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} 
            />
            {errors.email && <p className="text-red-500 text-xs font-medium mt-1">{errors.email.message}</p>}
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
              className="rounded-xl h-11 bg-slate-900 hover:bg-slate-800 text-white px-8 shadow-sm transition-all active:scale-95"
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
