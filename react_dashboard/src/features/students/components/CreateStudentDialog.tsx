import { useRef, useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { studentApi } from '../api/studentApi';
import { classApi } from '@/features/classes/api/classApi';
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
import { Loader2, Camera } from 'lucide-react';
import { getApiError } from '@/lib/utils';

const studentSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  email: z.string().email('Email invalide').optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  class_id: z.string().optional(),
});

type StudentForm = z.infer<typeof studentSchema>;

interface CreateStudentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateStudentDialog({ open, onOpenChange }: CreateStudentDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();

  const { data: classes, isLoading: isLoadingClasses } = useQuery({
    queryKey: ['classes'],
    queryFn: classApi.getAll,
    enabled: open,
  });

  const { register, handleSubmit, formState: { errors }, reset } = useForm<StudentForm>({
    resolver: zodResolver(studentSchema),
    defaultValues: { first_name: '', last_name: '', email: '', phone: '', class_id: '' }
  });

  const uploadPhotoMutation = useMutation({
    mutationFn: ({ id, file }: { id: string; file: File }) => studentApi.uploadPhoto(id, file),
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['students'] }),
  });

  const createMutation = useMutation({
    mutationFn: studentApi.create,
    onSuccess: (student) => {
      if (photoFile) {
        uploadPhotoMutation.mutate({ id: student.id, file: photoFile });
      } else {
        queryClient.invalidateQueries({ queryKey: ['students'] });
      }
      handleClose();
    },
    onError: (error: any) => {
      const detail = getApiError(error);
      setServerError(Array.isArray(detail) ? detail[0]?.msg : detail || 'Erreur lors de la création');
    }
  });

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhotoFile(file);
    setPhotoPreview(URL.createObjectURL(file));
  };

  const handleClose = () => {
    reset();
    setPhotoFile(null);
    setPhotoPreview(null);
    setServerError(null);
    onOpenChange(false);
  };

  const onSubmit = (data: StudentForm) => {
    setServerError(null);
    createMutation.mutate({
      first_name: data.first_name,
      last_name: data.last_name,
      email: data.email || undefined,
      phone: data.phone || undefined,
      class_id: data.class_id || undefined,
    });
  };

  const isPending = createMutation.isPending || uploadPhotoMutation.isPending;

  return (
    <Dialog open={open} onOpenChange={(val) => { if (!val) handleClose(); }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl">
        <DialogHeader>
          <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">Ajouter un élève</DialogTitle>
          <DialogDescription className="text-slate-500">
            Créez un profil élève manuellement et affectez-le à une classe.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5 pt-4">
          {serverError && (
            <div className="p-3 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm animate-in fade-in zoom-in duration-200">
              {serverError}
            </div>
          )}

          {/* Photo */}
          <div className="flex flex-col items-center gap-2">
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              className="relative w-20 h-20 rounded-full overflow-hidden border-2 border-dashed border-slate-300 hover:border-slate-500 bg-slate-50 flex items-center justify-center transition-colors group"
            >
              {photoPreview ? (
                <img src={photoPreview} alt="Aperçu" className="w-full h-full object-cover" />
              ) : (
                <Camera className="w-7 h-7 text-slate-400 group-hover:text-slate-600 transition-colors" />
              )}
            </button>
            <span className="text-xs text-slate-400">Photo (optionnel)</span>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              onChange={handlePhotoChange}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="last_name" className="text-slate-700 font-medium">Nom</Label>
            <Input id="last_name" {...register('last_name')} placeholder="ex: Dupont"
              className={errors.last_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.last_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.last_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="first_name" className="text-slate-700 font-medium">Prénom</Label>
            <Input id="first_name" {...register('first_name')} placeholder="ex: Jean"
              className={errors.first_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.first_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.first_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="email" className="text-slate-700 font-medium">Email (optionnel)</Label>
            <Input id="email" type="email" placeholder="eleve@ecole.be" {...register('email')}
              className={errors.email ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.email && <p className="text-red-500 text-xs font-medium mt-1">{errors.email.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="phone" className="text-slate-700 font-medium">Téléphone (optionnel)</Label>
            <Input id="phone" type="tel" placeholder="ex: +32 470 00 00 00" {...register('phone')}
              className="border-slate-200 focus:border-slate-900 focus:ring-slate-900" />
          </div>

          <div className="space-y-2">
            <Label htmlFor="class_id" className="text-slate-700 font-medium">Classe</Label>
            <select id="class_id" {...register('class_id')}
              className="w-full h-10 px-3 py-2 bg-white border border-slate-200 rounded-md text-sm ring-offset-white focus:outline-none focus:ring-2 focus:ring-slate-900 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 transition-all">
              <option value="">-- Aucune classe --</option>
              {isLoadingClasses ? (
                <option disabled>Chargement des classes...</option>
              ) : (
                classes?.map((c) => (
                  <option key={c.id} value={c.id}>{c.name} {c.year ? `(${c.year})` : ''}</option>
                ))
              )}
            </select>
          </div>

          <DialogFooter className="gap-3 pt-4">
            <Button type="button" variant="outline" onClick={handleClose} className="rounded-xl h-11 border-slate-200">
              Annuler
            </Button>
            <Button type="submit" disabled={isPending}
              className="rounded-xl h-11 bg-slate-900 hover:bg-slate-800 text-white px-8 shadow-sm transition-all active:scale-95">
              {isPending ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Création...</>) : 'Sauvegarder'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
