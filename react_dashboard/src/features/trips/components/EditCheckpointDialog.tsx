import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { tripApi, type CheckpointTimelineEntry } from '../api/tripApi';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Loader2 } from 'lucide-react';

const schema = z.object({
  name: z.string().min(1, 'Le nom est requis'),
  description: z.string().optional(),
});

type CheckpointForm = z.infer<typeof schema>;

interface Props {
  tripId: string;
  checkpoint: CheckpointTimelineEntry | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function EditCheckpointDialog({ tripId, checkpoint, open, onOpenChange }: Props) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [hasInitialized, setHasInitialized] = useState(false);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset } = useForm<CheckpointForm>({
    resolver: zodResolver(schema),
  });

  useEffect(() => {
    if (open && checkpoint && !hasInitialized) {
      reset({ name: checkpoint.name, description: checkpoint.description ?? '' });
      setHasInitialized(true);
    }
    if (!open) setHasInitialized(false);
  }, [open, checkpoint, hasInitialized, reset]);

  const mutation = useMutation({
    mutationFn: (data: CheckpointForm) => tripApi.updateCheckpoint(checkpoint!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trips', tripId, 'checkpoints-summary'] });
      onOpenChange(false);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Erreur lors de la modification';
      setServerError(msg);
    },
  });

  const onSubmit = (data: CheckpointForm) => {
    setServerError(null);
    mutation.mutate(data);
  };

  const handleOpenChange = (open: boolean) => {
    if (!open) setServerError(null);
    onOpenChange(open);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Modifier le checkpoint</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 pt-2">
          <div className="space-y-1">
            <Label htmlFor="edit-cp-name">Nom *</Label>
            <Input id="edit-cp-name" {...register('name')} />
            {errors.name && <p className="text-sm text-red-500">{errors.name.message}</p>}
          </div>
          <div className="space-y-1">
            <Label htmlFor="edit-cp-desc">Description</Label>
            <Textarea id="edit-cp-desc" rows={3} {...register('description')} />
          </div>
          {serverError && <p className="text-sm text-red-500">{serverError}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
              Annuler
            </Button>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Enregistrer
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
