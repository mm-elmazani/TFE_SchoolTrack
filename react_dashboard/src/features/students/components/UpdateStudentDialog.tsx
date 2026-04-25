import { useEffect, useRef, useState } from 'react';
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
import { Loader2, Camera } from 'lucide-react';
import { getApiError } from '@/lib/utils';

const studentSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  email: z.string().email('Email invalide').optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
});

type StudentForm = z.infer<typeof studentSchema>;

interface UpdateStudentDialogProps {
  student: Student | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function UpdateStudentDialog({ student, open, onOpenChange }: UpdateStudentDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [photoBlobUrl, setPhotoBlobUrl] = useState<string | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset } = useForm<StudentForm>({
    resolver: zodResolver(studentSchema),
  });

  // Charger les données de l'élève dans le formulaire
  useEffect(() => {
    if (student && open) {
      reset({
        first_name: student.first_name,
        last_name: student.last_name,
        email: student.email || '',
        phone: student.phone || '',
      });
      // Charger la photo via l'endpoint protégé si elle existe
      if (student.photo_url) {
        studentApi.getPhotoBlobUrl(student.id)
          .then(url => setPhotoBlobUrl(url))
          .catch(() => setPhotoBlobUrl(null));
      } else {
        setPhotoBlobUrl(null);
      }
      setPhotoPreview(null);
    }
  }, [student, open, reset]);

  // Libérer les blob URLs pour éviter les fuites mémoire
  useEffect(() => {
    return () => {
      if (photoBlobUrl) URL.revokeObjectURL(photoBlobUrl);
      if (photoPreview) URL.revokeObjectURL(photoPreview);
    };
  }, [photoBlobUrl, photoPreview]);

  const uploadPhotoMutation = useMutation({
    mutationFn: (file: File) => studentApi.uploadPhoto(student!.id, file),
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      // Recharger la nouvelle photo
      studentApi.getPhotoBlobUrl(updated.id)
        .then(url => { setPhotoBlobUrl(url); setPhotoPreview(null); })
        .catch(() => {});
    },
    onError: () => setServerError('Erreur lors de l\'upload de la photo'),
  });

  const updateMutation = useMutation({
    mutationFn: (data: StudentForm) => studentApi.update(student!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      onOpenChange(false);
    },
    onError: (error: any) => {
      setServerError(getApiError(error, 'Erreur lors de la modification'));
    }
  });

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const preview = URL.createObjectURL(file);
    setPhotoPreview(preview);
    uploadPhotoMutation.mutate(file);
  };

  const onSubmit = (data: StudentForm) => {
    setServerError(null);
    updateMutation.mutate({
      first_name: data.first_name,
      last_name: data.last_name,
      email: data.email || undefined,
      phone: data.phone || undefined,
    });
  };

  const displayPhoto = photoPreview || photoBlobUrl;

  return (
    <Dialog open={open} onOpenChange={(val) => { setServerError(null); onOpenChange(val); }}>
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

          {/* Photo */}
          <div className="flex flex-col items-center gap-2">
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              disabled={uploadPhotoMutation.isPending}
              className="relative w-20 h-20 rounded-full overflow-hidden border-2 border-dashed border-slate-300 hover:border-slate-500 bg-slate-50 flex items-center justify-center transition-colors group"
            >
              {uploadPhotoMutation.isPending ? (
                <Loader2 className="w-6 h-6 text-slate-400 animate-spin" />
              ) : displayPhoto ? (
                <img src={displayPhoto} alt="Photo élève" className="w-full h-full object-cover" />
              ) : (
                <Camera className="w-7 h-7 text-slate-400 group-hover:text-slate-600 transition-colors" />
              )}
            </button>
            <span className="text-xs text-slate-400">
              {displayPhoto ? 'Cliquer pour changer la photo' : 'Ajouter une photo'}
            </span>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              onChange={handlePhotoChange}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="last_name_update" className="text-slate-700 font-medium">Nom</Label>
            <Input id="last_name_update" {...register('last_name')} placeholder="ex: Dupont"
              className={errors.last_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.last_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.last_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="first_name_update" className="text-slate-700 font-medium">Prénom</Label>
            <Input id="first_name_update" {...register('first_name')} placeholder="ex: Jean"
              className={errors.first_name ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.first_name && <p className="text-red-500 text-xs font-medium mt-1">{errors.first_name.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="email_update" className="text-slate-700 font-medium">Email (optionnel)</Label>
            <Input id="email_update" type="email" placeholder="eleve@ecole.be" {...register('email')}
              className={errors.email ? 'border-red-500 bg-red-50/30' : 'border-slate-200 focus:border-slate-900 focus:ring-slate-900'} />
            {errors.email && <p className="text-red-500 text-xs font-medium mt-1">{errors.email.message}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="phone_update" className="text-slate-700 font-medium">Téléphone (optionnel)</Label>
            <Input id="phone_update" type="tel" placeholder="ex: +32 470 00 00 00" {...register('phone')}
              className="border-slate-200 focus:border-slate-900 focus:ring-slate-900" />
          </div>

          <DialogFooter className="gap-3 pt-4">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} className="rounded-xl h-11 border-slate-200">
              Annuler
            </Button>
            <Button type="submit" disabled={updateMutation.isPending}
              className="rounded-xl h-11 bg-slate-900 hover:bg-slate-800 text-white px-8 shadow-sm transition-all active:scale-95">
              {updateMutation.isPending ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Modification...</>) : 'Sauvegarder'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
